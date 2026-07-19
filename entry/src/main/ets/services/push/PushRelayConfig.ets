import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { buffer } from '@kit.ArkTS';
import { Log } from '../logging/Log';

const LOG_TAG: string = '[ArkDO][PushRelayConfig]';
// 随包分发的中继配置。**不进版本控制**(与 agconnect-services.json 同一处理方式):
// 中继地址与共享密钥属于部署信息,不该出现在开源仓库里。缺这个文件时推送功能自动降级为不可用,
// 其余功能不受影响——自建者可放自己的配置,或在设置页填自己的中继地址。
export const PUSH_RELAY_CONFIG_RAWFILE: string = 'relay-config.json';
const PREF_STORE_NAME: string = 'app_settings';
const PREF_KEY_CUSTOM_BASE: string = 'push_relay_custom_base';
// 是否已同意"通知内容经由本项目运营的中继转发"。仅在使用随包中继时需要这份告知——
// 用户自建中继时数据只经过他自己的服务器,无须向他声明。
const PREF_KEY_RELAY_CONSENT: string = 'push_relay_consent_v1';

export interface PushRelayConfig {
  baseUrl: string;
  // 仅在使用随包配置的中继时才带上;指向自建中继时一律不发(见 resolve 的说明)。
  apiKey: string;
}

interface PushRelayConfigPayload {
  baseUrl?: string;
  apiKey?: string;
}

let bundledConfig: PushRelayConfig = { baseUrl: '', apiKey: '' };

// 由 EntryAbility 在启动时调用一次。解析失败不抛异常:推送不可用不应拖垮启动。
export function loadPushRelayConfigFromRawContent(rawContent: Uint8Array): boolean {
  try {
    const text: string = buffer.from(rawContent as ArrayBufferLike).toString('utf8');
    const payload: PushRelayConfigPayload = JSON.parse(text) as PushRelayConfigPayload;
    const baseUrl: string = normalizeBaseUrl(typeof payload.baseUrl === 'string' ? payload.baseUrl : '');
    const apiKey: string = typeof payload.apiKey === 'string' ? payload.apiKey.trim() : '';
    bundledConfig = { baseUrl: baseUrl, apiKey: apiKey };
    Log.i(`${LOG_TAG} loaded bundled config hasBase=${baseUrl.length > 0} hasKey=${apiKey.length > 0}`);
    return baseUrl.length > 0;
  } catch (err) {
    Log.i(`${LOG_TAG} parse failed error=${JSON.stringify(err)}`);
    bundledConfig = { baseUrl: '', apiKey: '' };
    return false;
  }
}

// 解析出本次该用的中继配置。优先级:用户自填 > 随包配置 > 无(推送不可用)。
export function resolvePushRelayConfig(context: common.Context): PushRelayConfig {
  const custom: string = normalizeBaseUrl(readCustomBaseUrl(context));
  if (custom.length > 0) {
    // 安全要点:随包密钥只属于官方中继,绝不能发往用户自填的第三方地址,
    // 否则等于把密钥拱手送给任意服务器。自建者把服务端的 RELAY_API_KEY 留空即可。
    return { baseUrl: custom, apiKey: '' };
  }
  return bundledConfig;
}

export function isPushRelayConfigured(context: common.Context): boolean {
  return resolvePushRelayConfig(context).baseUrl.length > 0;
}

// 本次开启推送是否需要先征得同意:仅当用户没有自填中继(即将走本项目运营的中继)、
// 且此前没同意过时才需要。自建中继的用户数据只经过自己的服务器,不必打扰。
export function needsRelayConsent(context: common.Context): boolean {
  if (readCustomBaseUrl(context).length > 0) {
    return false;
  }
  return !isRelayConsentAccepted(context);
}

export function isRelayConsentAccepted(context: common.Context): boolean {
  try {
    const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
    return store.getSync(PREF_KEY_RELAY_CONSENT, false) as boolean;
  } catch (err) {
    Log.i(`${LOG_TAG} read consent failed error=${JSON.stringify(err)}`);
    // 读不到就当没同意过:宁可多问一次,也不能替用户默认接受。
    return false;
  }
}

export function saveRelayConsent(context: common.Context, accepted: boolean): void {
  try {
    const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
    store.putSync(PREF_KEY_RELAY_CONSENT, accepted);
    store.flush();
    Log.i(`${LOG_TAG} relay consent saved accepted=${accepted}`);
  } catch (err) {
    Log.i(`${LOG_TAG} save consent failed error=${JSON.stringify(err)}`);
  }
}

export function readCustomBaseUrl(context: common.Context): string {
  try {
    const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
    return store.getSync(PREF_KEY_CUSTOM_BASE, '') as string;
  } catch (err) {
    Log.i(`${LOG_TAG} read custom base failed error=${JSON.stringify(err)}`);
    return '';
  }
}

// 返回是否保存成功。空串表示清除自填地址、回落到随包配置。
export function saveCustomBaseUrl(context: common.Context, baseUrl: string): boolean {
  const normalized: string = normalizeBaseUrl(baseUrl);
  if (baseUrl.trim().length > 0 && normalized.length === 0) {
    return false;
  }
  try {
    const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_STORE_NAME });
    store.putSync(PREF_KEY_CUSTOM_BASE, normalized);
    store.flush();
    Log.i(`${LOG_TAG} custom base saved hasValue=${normalized.length > 0}`);
    return true;
  } catch (err) {
    Log.i(`${LOG_TAG} save custom base failed error=${JSON.stringify(err)}`);
    return false;
  }
}

// 只接受 https:一来中继承载通知明文,二来 .app 域本身就被 HSTS 强制 https。
function normalizeBaseUrl(raw: string): string {
  const trimmed: string = raw.trim().replace(/\/+$/, '');
  if (trimmed.length === 0) {
    return '';
  }
  if (!trimmed.startsWith('https://')) {
    return '';
  }
  return trimmed;
}
