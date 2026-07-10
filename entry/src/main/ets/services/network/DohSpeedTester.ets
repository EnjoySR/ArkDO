import { Log } from '../logging/Log';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

const LOG_TAG: string = '[ArkDO][DohTest]';
// 测速探针域名:解析 linux.do 本身既测延迟又验证"能否正确解析目标站"。
const PROBE_DOMAIN: string = 'linux.do';
const PER_REQUEST_TIMEOUT_MS: number = 3000;
const SAMPLE_COUNT: number = 3;

/** 单次测速结果:latencyMs 为成功样本的最小往返(-1 表示全部失败/超时)。 */
export interface DohTestResult {
  ok: boolean;
  latencyMs: number;
  message: string;
}

/**
 * DoH 测速:向 DoH 端点发送符合 RFC 8484 的 wireformat 查询(GET ?dns=base64url),
 * 计量往返延迟并校验应答含解析结果。用 wireformat 而非 JSON,因自定义端点不保证支持 JSON。
 */
export class DohSpeedTester {
  /** 对单个 DoH URL 测速:多次采样取成功样本最小值,首次(含 TLS 握手)不计入。 */
  static async test(url: string): Promise<DohTestResult> {
    if (!url.startsWith('https://')) {
      return { ok: false, latencyMs: -1, message: '地址无效' };
    }
    const query: string = DohSpeedTester.buildQueryParam(PROBE_DOMAIN);
    const requestUrl: string = url.indexOf('?') >= 0 ? `${url}&dns=${query}` : `${url}?dns=${query}`;

    const latencies: number[] = [];
    let lastMessage: string = '请求失败';
    for (let i = 0; i < SAMPLE_COUNT; i++) {
      const sample: DohTestResult = await DohSpeedTester.probeOnce(requestUrl);
      if (sample.ok) {
        // 丢弃第一次(冷连接/TLS 握手偏高),只用后续样本;若仅第一次成功则退而用之。
        if (i > 0 || latencies.length === 0) {
          latencies.push(sample.latencyMs);
        }
      } else {
        lastMessage = sample.message;
      }
    }

    if (latencies.length === 0) {
      return { ok: false, latencyMs: -1, message: lastMessage };
    }
    let best: number = latencies[0];
    for (const v of latencies) {
      if (v < best) {
        best = v;
      }
    }
    return { ok: true, latencyMs: best, message: '解析正常' };
  }

  // 单次探测:发 wireformat GET,校验 200 + 应答区 ANCOUNT>0(确有解析结果)。
  private static async probeOnce(requestUrl: string): Promise<DohTestResult> {
    const request: http.HttpRequest = http.createHttp();
    const start: number = Date.now();
    try {
      const response: http.HttpResponse = await request.request(requestUrl, {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'application/dns-message' },
        connectTimeout: PER_REQUEST_TIMEOUT_MS,
        readTimeout: PER_REQUEST_TIMEOUT_MS,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      const elapsed: number = Date.now() - start;
      if (response.responseCode !== 200) {
        return { ok: false, latencyMs: -1, message: `HTTP ${response.responseCode}` };
      }
      const answers: number = DohSpeedTester.readAnswerCount(response.result);
      if (answers <= 0) {
        return { ok: false, latencyMs: -1, message: '无解析结果' };
      }
      return { ok: true, latencyMs: elapsed, message: '解析正常' };
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      Log.i(`${LOG_TAG} probe failed code=${error.code}`);
      // 2300028 等超时类错误统一归为"超时/不可达"。
      return { ok: false, latencyMs: -1, message: '超时/不可达' };
    } finally {
      request.destroy();
    }
  }

  // 读 DNS 应答报文头部第 6~7 字节(ANCOUNT),>0 即表示服务器返回了解析记录。
  private static readAnswerCount(result: string | Object | ArrayBuffer): number {
    if (!(result instanceof ArrayBuffer)) {
      return 0;
    }
    const bytes: Uint8Array = new Uint8Array(result);
    if (bytes.length < 12) {
      return 0;
    }
    return (bytes[6] << 8) | bytes[7];
  }

  // 构造 A 记录查询报文并转 base64url(无 padding),供 GET ?dns= 使用。
  private static buildQueryParam(domain: string): string {
    const packet: Uint8Array = DohSpeedTester.buildQuery(domain);
    const helper: util.Base64Helper = new util.Base64Helper();
    const base64: string = helper.encodeToStringSync(packet, util.Type.BASIC);
    return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  // 拼一个标准 DNS 查询报文:12 字节头(RD=1,QDCOUNT=1)+ 问题区(QNAME + A + IN)。
  private static buildQuery(domain: string): Uint8Array {
    const labels: string[] = domain.split('.');
    let qnameLen: number = 0;
    for (const label of labels) {
      qnameLen += 1 + label.length;
    }
    qnameLen += 1; // 结尾 0 长度字节
    const packet: Uint8Array = new Uint8Array(12 + qnameLen + 4);
    // Header: ID=0, flags=0x0100(RD), QDCOUNT=1, 其余 0。
    packet[2] = 0x01;
    packet[5] = 0x01;
    // Question QNAME。
    let offset: number = 12;
    for (const label of labels) {
      packet[offset] = label.length;
      offset += 1;
      for (let i = 0; i < label.length; i++) {
        packet[offset] = label.charCodeAt(i);
        offset += 1;
      }
    }
    packet[offset] = 0x00;
    offset += 1;
    // QTYPE=A(0x0001), QCLASS=IN(0x0001)。
    packet[offset + 1] = 0x01;
    packet[offset + 3] = 0x01;
    return packet;
  }
}
