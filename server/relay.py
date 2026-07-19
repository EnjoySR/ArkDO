#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Web Push -> Huawei Push Kit relay.
Registers subscriptions, receives/decrypts Discourse web push, forwards notification messages.
Listens on 127.0.0.1:8787; put a TLS reverse proxy (e.g. Caddy) in front and forward
/wp/* and /subscription/* here. See server/README.md for deployment.
Deps: stdlib + `cryptography` (system site-packages). No pip needed.
"""
import json, os, base64, secrets, threading, datetime, time, urllib.parse, urllib.request, urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from cryptography.hazmat.primitives.asymmetric import ec, padding
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

BASE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(BASE, "subs.json")
LOG = os.path.join(BASE, "relay.log")
# 本中继对外的 https 基址,如 https://push.example.com。**必须显式配置**:
# 它会被拼进订阅 endpoint 交给 Discourse,填错/漏填会让推送投递到别人的服务器。
# 故不设默认值——没配就拒绝启动(见 main),而不是悄悄回落到某个具体域名。
PUBLIC_BASE = os.environ.get("RELAY_PUBLIC_BASE", "").rstrip("/")
LISTEN = ("127.0.0.1", 8787)
# 客户端调 /subscription/* 需带的共享密钥(X-ArkDO-Key)。留空则不鉴权(自建者可自行决定)。
# 注意:密钥随 App 分发,能被反编译取出——它拦得住扫描器和脚本化滥用,拦不住有心人,
# 故必须与限流、容量上限一起用,不能当作真正的身份认证。
RELAY_API_KEY = os.environ.get("RELAY_API_KEY", "")
# 单 IP 限流:窗口内最多多少次 /subscription/* 请求。
RATE_LIMIT_WINDOW_SEC = int(os.environ.get("RELAY_RATE_WINDOW", "60"))
RATE_LIMIT_MAX = int(os.environ.get("RELAY_RATE_MAX", "20"))
# 测试推送的单订阅冷却(秒)。比通用限流严得多:每调一次就真往设备推一条通知,
# 连点会变成推送轰炸并白耗 Push Kit 配额。按 subId 计而不是按 IP——换网络、
# 重装应用都绕不开。设 0 关闭。
TEST_PUSH_COOLDOWN_SEC = int(os.environ.get("RELAY_TEST_COOLDOWN", "60"))
# 订阅总量上限:防止磁盘与密钥生成被无限薅。达到上限后先尝试清理陈旧记录。
MAX_SUBSCRIPTIONS = int(os.environ.get("RELAY_MAX_SUBS", "5000"))
# 陈旧记录清理:已停用且超过这个天数没更新的,直接丢弃。
STALE_DISABLED_DAYS = int(os.environ.get("RELAY_STALE_DAYS", "30"))
# 日志轮转:超过这个字节数就滚存一份 .1(只留一代)。
LOG_MAX_BYTES = int(os.environ.get("RELAY_LOG_MAX_BYTES", str(2 * 1024 * 1024)))
# 是否把通知标题等用户内容写进日志。默认关闭,仅排障时临时打开。
LOG_CONTENT = os.environ.get("RELAY_LOG_CONTENT", "") == "1"
PUSHKIT_PROJECT_ID = os.environ.get("PUSHKIT_PROJECT_ID", "")
PUSHKIT_CLIENT_ID = os.environ.get("PUSHKIT_CLIENT_ID", "")
PUSHKIT_CLIENT_SECRET = os.environ.get("PUSHKIT_CLIENT_SECRET", "")
PUSHKIT_SERVICE_ACCOUNT_FILE = os.environ.get("PUSHKIT_SERVICE_ACCOUNT_FILE", "")
# 消息分类分流(AGC 需为每个分类单独申请权益,且华为对每条 messages:send 都校验 category)。
#   PUSHKIT_CATEGORY         私信类通知用(即时聊天,已审核通过)
#   PUSHKIT_CATEGORY_DEFAULT 其余通知(回复/@/点赞等内容更新)用。默认回落到 IM,
#                            使当前行为与分流前完全一致;待"订阅"分类审核通过后,
#                            只需在 wp-relay.env 里设成订阅的枚举值即可切换,无需改代码或重打 App。
PUSHKIT_CATEGORY = os.environ.get("PUSHKIT_CATEGORY", "IM")
PUSHKIT_CATEGORY_DEFAULT = os.environ.get("PUSHKIT_CATEGORY_DEFAULT", "") or PUSHKIT_CATEGORY
# 测试推送点击后的落点(站内相对路径)。默认指向 ArkDO 主帖里作者留的那一楼;
# 自建者可改成自己的帖子,或设为空串让点击只打开 App 首页而不跳转。
TEST_PUSH_URL = os.environ.get("RELAY_TEST_PUSH_URL", "/t/topic/2590051/121")
# Discourse 发来的 message 不含 notification_type,只能从 icon 路径反推类型名:
#   icon = .../push-notifications/<type_name>.png(该类型无图标时回落成 discourse.png)
# 这两个类型名对应 Discourse 的 private_message(6)/invited_to_private_message(7)。
PRIVATE_MESSAGE_ICON_NAMES = ("private_message", "invited_to_private_message")
PUSHKIT_TOKEN_URL = "https://oauth-login.cloud.huawei.com/oauth2/v3/token"
PUSHKIT_SEND_URL = "https://push-api.cloud.huawei.com/v3/%s/messages:send"
# 可重入锁:register/disable 等"读-改-写"必须整段持锁,而内部还会调 load_db/save_db,故用 RLock。
# 原先 load_db 与 save_db 各自单独加锁,中间是放开的 → 并发写会丢更新(后写者覆盖先写者)。
_lock = threading.RLock()
_rate_lock = threading.Lock()
_rate_buckets = {}
# subId -> 上次测试推送的时间戳
_test_push_last = {}
_token_lock = threading.Lock()
_access_token = ""
_access_token_expire_at = 0.0
_service_account = None


def b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


def b64u_dec(s: str) -> bytes:
    s += "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s)


def log(msg: str):
    line = "[%sZ] %s" % (datetime.datetime.utcnow().isoformat(), msg)
    print(line, flush=True)
    try:
        # 轮转:日志里会出现用户相关信息,不能无限堆积。只留一代 .1,超限即滚存。
        if os.path.exists(LOG) and os.path.getsize(LOG) > LOG_MAX_BYTES:
            os.replace(LOG, LOG + ".1")
        with open(LOG, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


def load_db() -> dict:
    with _lock:
        if os.path.exists(DB):
            try:
                return json.load(open(DB))
            except Exception:
                return {}
        return {}


def save_db(d: dict):
    with _lock:
        tmp = DB + ".tmp"
        json.dump(d, open(tmp, "w"))
        os.replace(tmp, DB)


def utc_now() -> str:
    return datetime.datetime.utcnow().isoformat() + "Z"


def rate_limit_ok(client_ip: str) -> bool:
    """单 IP 滑动窗口限流。RELAY_RATE_MAX<=0 表示关闭。"""
    if RATE_LIMIT_MAX <= 0:
        return True
    now = time.time()
    with _rate_lock:
        hits = [t for t in _rate_buckets.get(client_ip, []) if now - t < RATE_LIMIT_WINDOW_SEC]
        # 顺手回收其它 IP 的过期桶,避免字典无限增长。
        if len(_rate_buckets) > 1000:
            for ip in [k for k, v in _rate_buckets.items()
                       if not any(now - t < RATE_LIMIT_WINDOW_SEC for t in v)]:
                _rate_buckets.pop(ip, None)
        if len(hits) >= RATE_LIMIT_MAX:
            _rate_buckets[client_ip] = hits
            return False
        hits.append(now)
        _rate_buckets[client_ip] = hits
        return True


def test_push_cooldown_left(sub_id: str) -> int:
    """测试推送冷却:返回还需等待的秒数,0 表示可以发。放行时顺手记账。"""
    if TEST_PUSH_COOLDOWN_SEC <= 0 or not sub_id:
        return 0
    now = time.time()
    with _rate_lock:
        last = _test_push_last.get(sub_id, 0.0)
        left = int(TEST_PUSH_COOLDOWN_SEC - (now - last))
        if left > 0:
            return left
        # 顺手回收过期条目,避免字典随订阅数无限增长。
        if len(_test_push_last) > 1000:
            for sid in [k for k, t in _test_push_last.items()
                        if now - t > TEST_PUSH_COOLDOWN_SEC]:
                _test_push_last.pop(sid, None)
        _test_push_last[sub_id] = now
        return 0


def api_key_ok(headers) -> bool:
    """校验 /subscription/* 的共享密钥。未配置 RELAY_API_KEY 时不鉴权。"""
    if not RELAY_API_KEY:
        return True
    provided = headers.get("X-ArkDO-Key") or ""
    # 定长比较,避免因比较耗时差异泄露密钥前缀。
    return secrets.compare_digest(provided, RELAY_API_KEY)


def prune_subscriptions(db: dict) -> int:
    """丢弃"已停用且长期无更新"的记录。返回清理条数。调用方需持 _lock。"""
    if STALE_DISABLED_DAYS <= 0:
        return 0
    cutoff = datetime.datetime.utcnow() - datetime.timedelta(days=STALE_DISABLED_DAYS)
    dropped = []
    for sid, rec in list(db.items()):
        if rec.get("enabled", True):
            continue
        stamp = str(rec.get("updated") or rec.get("disabled") or "").rstrip("Z")
        try:
            if datetime.datetime.fromisoformat(stamp) < cutoff:
                dropped.append(sid)
        except Exception:
            continue
    for sid in dropped:
        db.pop(sid, None)
    if dropped:
        log("pruned %d stale subscriptions" % len(dropped))
    return len(dropped)


def public_endpoint(sid: str) -> str:
    return "%s/wp/%s" % (PUBLIC_BASE, sid)


def response_for_subscription(sid: str, rec: dict) -> dict:
    return {
        "subId": sid,
        "endpoint": public_endpoint(sid),
        "p256dh": rec["p256dh"],
        "auth": rec["auth"],
    }


def is_same_user(rec: dict, user_id, username: str) -> bool:
    if user_id:
        rec_user_id = rec.get("user_id")
        return rec_user_id in (None, "", user_id)
    if username:
        rec_username = rec.get("username")
        return rec_username in (None, "", username)
    return True


def update_subscription_metadata(rec: dict, device_token: str, user_id, username: str):
    rec["device_token"] = device_token
    if user_id:
        rec["user_id"] = user_id
    if username:
        rec["username"] = username
    rec["enabled"] = True
    rec["updated"] = utc_now()


def register(device_token, user_id=None, username="", existing_sub_id=""):
    # 整段持锁:这是"读-改-写",load 与 save 之间若放开锁,并发注册会互相覆盖(丢更新)。
    with _lock:
        db = load_db()
        if existing_sub_id and existing_sub_id in db:
            rec = db[existing_sub_id]
            if device_token and is_same_user(rec, user_id, username):
                update_subscription_metadata(rec, device_token, user_id, username)
                save_db(db)
                return existing_sub_id, rec
        if device_token:
            for sid, rec in db.items():
                if rec.get("device_token") == device_token and is_same_user(rec, user_id, username) and rec.get("enabled", True):
                    update_subscription_metadata(rec, device_token, user_id, username)
                    save_db(db)
                    return sid, rec

        # 新建前先清陈旧记录,再看容量。避免被无限创建撑爆磁盘/空耗密钥生成。
        if len(db) >= MAX_SUBSCRIPTIONS:
            prune_subscriptions(db)
        if len(db) >= MAX_SUBSCRIPTIONS:
            log("register refused: subscription cap reached (%d)" % len(db))
            raise RuntimeError("subscription cap reached")

        priv = ec.generate_private_key(ec.SECP256R1())
        ua_pub = priv.public_key().public_bytes(
            serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
        )
        auth = secrets.token_bytes(16)
        priv_pem = priv.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        ).decode()
        sid = b64u(secrets.token_bytes(9))
        rec = {
            "priv_pem": priv_pem,
            "p256dh": b64u(ua_pub),
            "auth": b64u(auth),
            "device_token": device_token,
            "user_id": user_id or "",
            "username": username or "",
            "enabled": True,
            "created": utc_now(),
            "updated": utc_now(),
        }
        db[sid] = rec
        save_db(db)
        return sid, rec


def find_subscription(db: dict, sub_id: str, endpoint: str):
    if sub_id and sub_id in db:
        return sub_id, db[sub_id]
    if endpoint:
        for sid, rec in db.items():
            if public_endpoint(sid) == endpoint:
                return sid, rec
    return "", None


def disable_subscription(sub_id: str, endpoint: str, user_id=None, username="") -> bool:
    # 同 register:读-改-写必须整段持锁。
    with _lock:
        db = load_db()
        sid, rec = find_subscription(db, sub_id, endpoint)
        if not sid or rec is None:
            return False
        if not is_same_user(rec, user_id, username):
            log("disable denied sid=%s requested_user=%s stored_user=%s" % (sid, user_id or username, rec.get("user_id") or rec.get("username")))
            return False
        # 私钥已无用:停用后不会再有投递需要解密,留着只是多一份泄露面。
        rec.pop("priv_pem", None)
        rec["enabled"] = False
        rec["disabled"] = utc_now()
        rec["updated"] = utc_now()
        save_db(db)
        return True


def pushkit_configured() -> bool:
    return bool(pushkit_project_id() and PUSHKIT_SERVICE_ACCOUNT_FILE)


def http_json(req: urllib.request.Request, timeout=8) -> dict:
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8", "replace")
        return json.loads(raw or "{}")


def pushkit_project_id() -> str:
    if PUSHKIT_PROJECT_ID:
        return PUSHKIT_PROJECT_ID
    if PUSHKIT_SERVICE_ACCOUNT_FILE:
        try:
            return load_service_account().get("project_id", "")
        except Exception:
            return ""
    return ""


def load_service_account() -> dict:
    global _service_account
    if _service_account is not None:
        return _service_account
    if not PUSHKIT_SERVICE_ACCOUNT_FILE:
        raise RuntimeError("missing PUSHKIT_SERVICE_ACCOUNT_FILE")
    with open(PUSHKIT_SERVICE_ACCOUNT_FILE) as f:
        data = json.load(f)
    required = ("key_id", "private_key", "sub_account", "token_uri")
    missing = [k for k in required if not data.get(k)]
    if missing:
        raise RuntimeError("service account missing: %s" % ",".join(missing))
    _service_account = data
    return _service_account


def create_service_account_jwt(private_key_pem: str, key_id: str, sub_account: str,
                               token_uri: str, now=None, ttl=3600) -> str:
    iat = int(time.time() if now is None else now)
    header = {"alg": "PS256", "typ": "JWT", "kid": key_id}
    payload = {
        "iss": sub_account,
        "aud": token_uri,
        "iat": iat,
        "exp": iat + ttl,
    }
    header_b64 = b64u(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    payload_b64 = b64u(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signing_input = ("%s.%s" % (header_b64, payload_b64)).encode("ascii")
    private_key = serialization.load_pem_private_key(private_key_pem.encode("utf-8"), password=None)
    signature = private_key.sign(
        signing_input,
        padding.PSS(mgf=padding.MGF1(hashes.SHA256()), salt_length=32),
        hashes.SHA256(),
    )
    return "%s.%s.%s" % (header_b64, payload_b64, b64u(signature))


def get_pushkit_authorization_token() -> str:
    global _access_token, _access_token_expire_at
    now = time.time()
    with _token_lock:
        if _access_token and now < _access_token_expire_at - 120:
            return _access_token
        service_account = load_service_account()
        token = create_service_account_jwt(
            private_key_pem=service_account["private_key"],
            key_id=service_account["key_id"],
            sub_account=service_account["sub_account"],
            token_uri=service_account.get("token_uri") or PUSHKIT_TOKEN_URL,
        )
        expires_in = 3600
        _access_token = token
        _access_token_expire_at = now + expires_in
        return _access_token


def clean_text(value, limit: int) -> str:
    if not isinstance(value, str):
        return ""
    value = value.replace("\r", " ").strip()
    if len(value) <= limit:
        return value
    return value[:limit - 1] + "…"


def same_linuxdo_url(url: str) -> bool:
    parsed = urllib.parse.urlparse(url)
    return parsed.scheme in ("http", "https") and parsed.netloc.lower() == "linux.do"


def build_click_data(message: dict, title: str) -> dict:
    raw_url = clean_text(message.get("url"), 500)
    if not raw_url:
        return {}
    base_url = clean_text(message.get("base_url"), 120) or "https://linux.do"
    if raw_url.startswith("/"):
        target_url = "%s%s" % (base_url.rstrip("/"), raw_url)
    else:
        target_url = raw_url
    if not same_linuxdo_url(target_url):
        return {}
    data = {
        "arkdo_url": target_url,
        "arkdo_source": "linuxdo"
    }
    if title:
        data["arkdo_title"] = title
    return data


def notification_icon_name(message: dict) -> str:
    """从 icon URL 反推 Discourse 通知类型名。取不到/取不准时返回空串。"""
    icon = message.get("icon")
    if not isinstance(icon, str) or not icon:
        return ""
    tail = icon.split("?")[0].rsplit("/", 1)[-1]
    if not tail.endswith(".png"):
        return ""
    return tail[:-4].strip().lower()


def resolve_category(message: dict) -> str:
    """按通知类型选消息分类:私信走 IM,其余走默认分类。

    认不出类型时一律回落 IM(现状),宁可用高权益分类也不误降级——降错了会让本该
    强提醒的私信变成弱提醒。icon 为 discourse.png 表示该类型没有专属图标,同样认不出。
    """
    name = notification_icon_name(message)
    if not name or name == "discourse":
        return PUSHKIT_CATEGORY
    if name in PRIVATE_MESSAGE_ICON_NAMES:
        return PUSHKIT_CATEGORY
    return PUSHKIT_CATEGORY_DEFAULT


def forward_pushkit(sid: str, rec: dict, message: dict):
    device_token = rec.get("device_token")
    if not device_token:
        log("PUSHKIT sid=%s skipped: no device token" % sid)
        return False
    if not pushkit_configured():
        log("PUSHKIT sid=%s skipped: env not configured" % sid)
        return False
    title = clean_text(message.get("title"), 128) or "LINUX DO"
    body = clean_text(message.get("body"), 1024)
    click_action = {
        "actionType": 0
    }
    click_data = build_click_data(message, title)
    if click_data:
        click_action["data"] = click_data
    category = resolve_category(message)
    # 类型名与选中分类都不含用户内容,固定记录:便于核对分流是否按预期命中。
    log("PUSHKIT sid=%s type=%s category=%s" % (sid, notification_icon_name(message) or "?", category))
    req_body = {
        "payload": {
            "notification": {
                "category": category,
                "title": title,
                "body": body,
                "clickAction": click_action
            }
        },
        "target": {
            "token": [device_token]
        },
        "pushOptions": {
            "testMessage": False
        }
    }
    try:
        token = get_pushkit_authorization_token()
        req = urllib.request.Request(
            PUSHKIT_SEND_URL % pushkit_project_id(),
            data=json.dumps(req_body, ensure_ascii=False).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Authorization": "Bearer %s" % token,
                "push-type": "0",
            },
            method="POST",
        )
        resp = http_json(req)
        log("PUSHKIT sid=%s sent code=%s msg=%s" % (sid, resp.get("code"), resp.get("msg")))
        return str(resp.get("code")) == "80000000"
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:500]
        log("PUSHKIT sid=%s failed: HTTP %s %s" % (sid, e.code, detail))
        return False
    except Exception as e:
        log("PUSHKIT sid=%s failed: %r" % (sid, e))
        return False


def summarize_message(message: dict) -> str:
    """日志用摘要。默认不落通知正文——标题里含发帖人昵称与话题名,属用户内容,
    不该长期堆在服务器磁盘上。排障时把 RELAY_LOG_CONTENT=1 打开即可看到明文。"""
    url = clean_text(message.get("url"), 160)
    if LOG_CONTENT:
        return json.dumps({"title": clean_text(message.get("title"), 160), "url": url},
                          ensure_ascii=False)
    title = clean_text(message.get("title"), 160)
    return json.dumps({"titleLen": len(title), "url": url}, ensure_ascii=False)


def decrypt_webpush(body: bytes, priv_pem: str, auth_b64: str, ua_pub_b64: str) -> bytes:
    """RFC 8291 (webpush) + RFC 8188 (aes128gcm) receiver."""
    salt = body[0:16]
    idlen = body[20]
    as_pub = body[21:21 + idlen]          # sender ephemeral P-256 pubkey (65B)
    ciphertext = body[21 + idlen:]
    priv = serialization.load_pem_private_key(priv_pem.encode(), password=None)
    as_pub_key = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), as_pub)
    shared = priv.exchange(ec.ECDH(), as_pub_key)
    auth = b64u_dec(auth_b64)
    ua_pub = b64u_dec(ua_pub_b64)
    ikm = HKDF(hashes.SHA256(), 32, auth,
               b"WebPush: info\x00" + ua_pub + as_pub).derive(shared)
    cek = HKDF(hashes.SHA256(), 16, salt,
               b"Content-Encoding: aes128gcm\x00").derive(ikm)
    nonce = HKDF(hashes.SHA256(), 12, salt,
                 b"Content-Encoding: nonce\x00").derive(ikm)
    pt = AESGCM(cek).decrypt(nonce, ciphertext, None)
    pt = pt.rstrip(b"\x00")
    if pt and pt[-1] in (1, 2):           # strip RFC8188 record delimiter
        pt = pt[:-1]
    return pt


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "cdn"

    def log_message(self, *a):
        pass

    def _send(self, code, obj=None):
        self.send_response(code)
        if obj is not None:
            data = json.dumps(obj).encode()
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_header("Content-Length", "0")
            self.end_headers()

    def do_GET(self):
        xff = self.headers.get("X-Forwarded-For", "?")
        ua = (self.headers.get("User-Agent", "") or "")[:80]
        log("GET %s xff=%s ua=%s" % (self.path, xff, ua))
        p = self.path.split("?")[0]
        if p == "/wp/health":
            self._send(200, {"ok": True})
        elif p == "/wp/probe":
            # 可预览探针页:用于验证 Discourse 服务端能否出站访问本中继(让它 onebox 抓一次)。
            # 带 og 标签只是为了让 onebox 认可这是可预览页面;不放任何具体域名,避免开源后泄露部署信息。
            html = (b"<!doctype html><html><head>"
                    b"<meta property=\"og:title\" content=\"ArkDO Relay Probe\">"
                    b"<meta property=\"og:description\" content=\"reachability probe\">"
                    b"<title>ArkDO Relay Probe</title></head><body>probe ok</body></html>")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(html)))
            self.end_headers()
            self.wfile.write(html)
        else:
            self._send(404)

    def do_HEAD(self):
        xff = self.headers.get("X-Forwarded-For", "?")
        log("HEAD %s xff=%s" % (self.path, xff))
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def client_ip(self) -> str:
        # 经 Caddy 反代,真实来源在 X-Forwarded-For 首段。
        xff = self.headers.get("X-Forwarded-For", "")
        if xff:
            return xff.split(",")[0].strip()
        return self.client_address[0] if self.client_address else "?"

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(n) if n else b""
        path = self.path.split("?")[0]

        # /subscription/* 与 /register 是客户端入口:限流 + 共享密钥。
        # /wp/* 是 Discourse 的投递入口,不能挂这两道闸——它既不会带我们的密钥,
        # 也不该被限流拦掉(拦掉会让 Discourse 记失败,连续失败满一天订阅会被删)。
        if path == "/register" or path.startswith("/subscription/"):
            ip = self.client_ip()
            if not rate_limit_ok(ip):
                log("rate limited ip=%s path=%s" % (ip, path))
                self._send(429, {"error": "rate limited"})
                return
            if not api_key_ok(self.headers):
                log("unauthorized ip=%s path=%s" % (ip, path))
                self._send(401, {"error": "unauthorized"})
                return

        if path == "/register" or path == "/subscription/ensure":
            try:
                j = json.loads(body or b"{}")
            except Exception:
                j = {}
            device_token = j.get("device_token") or j.get("deviceToken") or ""
            if not device_token:
                self._send(400, {"error": "missing device_token"})
                return
            user_id = j.get("user_id") or j.get("userId") or ""
            try:
                user_id = int(user_id) if user_id else ""
            except Exception:
                user_id = ""
            username = str(j.get("username") or "")[:80]
            sub_id = str(j.get("sub_id") or j.get("subId") or "")[:80]
            try:
                sid, rec = register(device_token, user_id, username, sub_id)
            except RuntimeError as e:
                # 容量上限:明确回 503,让客户端知道是服务端暂时不收,而不是参数错。
                self._send(503, {"error": str(e)})
                return
            log("ensure sid=%s device=%s user=%s:%s" % (sid, "yes" if rec.get("device_token") else "no", rec.get("user_id", ""), rec.get("username", "")))
            self._send(200, response_for_subscription(sid, rec))
        elif path == "/subscription/test":
            try:
                j = json.loads(body or b"{}")
            except Exception:
                j = {}
            sub_id = str(j.get("sub_id") or j.get("subId") or "")[:80]
            endpoint = str(j.get("endpoint") or "")[:300]
            device_token = str(j.get("device_token") or j.get("deviceToken") or "")
            user_id = j.get("user_id") or j.get("userId") or ""
            try:
                user_id = int(user_id) if user_id else ""
            except Exception:
                user_id = ""
            username = str(j.get("username") or "")[:80]
            if not sub_id or not endpoint or not device_token:
                self._send(400, {"success": False, "error": "missing subscription credentials"})
                return
            db = load_db()
            sid, rec = find_subscription(db, sub_id, endpoint)
            if not sid or rec is None:
                self._send(404, {"success": False, "error": "subscription not found"})
                return
            if public_endpoint(sid) != endpoint:
                log("test denied sid=%s reason=endpoint_mismatch" % sid)
                self._send(403, {"success": False, "error": "endpoint mismatch"})
                return
            if not is_same_user(rec, user_id, username):
                log("test denied sid=%s reason=user_mismatch requested_user=%s stored_user=%s" % (sid, user_id or username, rec.get("user_id") or rec.get("username")))
                self._send(403, {"success": False, "error": "user mismatch"})
                return
            if rec.get("device_token") != device_token:
                log("test denied sid=%s reason=device_mismatch token=yes" % sid)
                self._send(403, {"success": False, "error": "device mismatch"})
                return
            if not rec.get("enabled", True):
                self._send(409, {"success": False, "error": "subscription disabled"})
                return
            # 冷却放在所有权校验之后:先确认调用者确实拥有这条订阅,再计入冷却,
            # 免得别人拿错误的凭据乱调也能把真实用户的冷却顶掉。
            cooldown = test_push_cooldown_left(sid)
            if cooldown > 0:
                log("test cooldown sid=%s left=%ds" % (sid, cooldown))
                self._send(429, {"success": False, "error": "cooldown", "retryAfter": cooldown})
                return
            # 测试推送的落点:主帖里一个固定楼层(作者留的祝福语)。
            # 文案要明确引导点击——否则用户只当是条成功提示,不会想到点开还有内容。
            # 楼层一旦发布请勿删除:楼层号写死在这里,删了会跳到不存在的楼层。
            message = {
                "title": "ArkDO 推送已开启 🎉",
                "body": "点我看看,给你准备了一句话 →",
                "base_url": "https://linux.do",
                "url": TEST_PUSH_URL
            }
            log("test push sid=%s user=%s:%s token=yes" % (sid, rec.get("user_id", ""), rec.get("username", "")))
            ok = forward_pushkit(sid, rec, message)
            self._send(200 if ok else 502, {"success": ok})
        elif path == "/subscription/disable":
            try:
                j = json.loads(body or b"{}")
            except Exception:
                j = {}
            user_id = j.get("user_id") or j.get("userId") or ""
            try:
                user_id = int(user_id) if user_id else ""
            except Exception:
                user_id = ""
            ok = disable_subscription(
                str(j.get("sub_id") or j.get("subId") or "")[:80],
                str(j.get("endpoint") or "")[:300],
                user_id,
                str(j.get("username") or "")[:80],
            )
            self._send(200, {"success": ok})
        elif path.startswith("/wp/"):
            sid = path[len("/wp/"):]
            xff = self.headers.get("X-Forwarded-For", "?")
            log("POST /wp/%s from xff=%s (%dB)" % (sid, xff, len(body)))
            rec = load_db().get(sid)
            if not rec:
                log("push UNKNOWN sid=%s (%dB)" % (sid, len(body)))
                self._send(404)
                return
            if not rec.get("enabled", True):
                log("push DISABLED sid=%s" % sid)
                self._send(410)
                return
            self._send(201)                 # ack Discourse immediately
            try:
                pt = decrypt_webpush(body, rec["priv_pem"], rec["auth"], rec["p256dh"])
                message = json.loads(pt.decode("utf-8", "replace"))
                log("PUSH sid=%s OK: %s" % (sid, summarize_message(message)))
                threading.Thread(target=forward_pushkit, args=(sid, rec, message), daemon=True).start()
            except Exception as e:
                log("PUSH sid=%s DECRYPT-FAIL (%dB): %r" % (sid, len(body), e))
        else:
            self._send(404)


if __name__ == "__main__":
    # 早失败:PUBLIC_BASE 会被拼进订阅 endpoint 交给 Discourse。漏配就启动的话,
    # 订阅会以 "/wp/<subId>" 这样的相对地址注册出去,推送永远投不回来且极难排查。
    if not PUBLIC_BASE:
        raise SystemExit(
            "RELAY_PUBLIC_BASE is required, e.g. https://push.example.com\n"
            "It is the public https base of THIS relay and gets embedded in the\n"
            "subscription endpoint handed to Discourse. See server/README.md."
        )
    if not PUBLIC_BASE.startswith("https://"):
        raise SystemExit("RELAY_PUBLIC_BASE must start with https:// (got %r)" % PUBLIC_BASE)
    log("relay starting on %s:%d base=%s pushkit=%s"
        % (LISTEN[0], LISTEN[1], PUBLIC_BASE, "on" if pushkit_configured() else "off"))
    ThreadingHTTPServer(LISTEN, H).serve_forever()
