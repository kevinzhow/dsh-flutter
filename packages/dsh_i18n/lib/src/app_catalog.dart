import 'dsh_i18n.dart';

/// The namespace of this client's own copy: the screens dsh's web client does
/// not have (pairing, the phone session list). Everything else comes from the
/// catalog generated out of dsh's own dictionaries. Both languages are
/// required here; `test/app_catalog_test.dart` enforces that.
const appNamespace = 'app';

/// The product name shown to people. It is the ONE place the display name is
/// defined for Dart code; the platform manifests carry the same string (see
/// `apps/dsh_flutter/lib/src/app_identity.dart`).
const Map<String, DshText> appCatalog = {
  // pairing
  'pairing.title': (en: 'Connect to a host', zh: '连接主机'),
  'pairing.intro': (
    en: 'Run `dsh web` on the computer that hosts your sessions, then open or paste the launch link it prints.',
    zh: '在运行会话的电脑上执行 `dsh web`，然后打开或粘贴它打印出的启动链接。',
  ),
  'pairing.field.url': (en: 'Launch link or host address', zh: '启动链接或主机地址'),
  'pairing.field.url.placeholder': (
    en: 'http://host:port/?token=…',
    zh: 'http://主机:端口/?token=…',
  ),
  'pairing.field.token': (
    en: 'Launch token (if not in the link)',
    zh: '启动令牌（链接里没有时填写）',
  ),
  'pairing.action.connect': (en: 'Connect', zh: '连接'),
  'pairing.action.paste': (en: 'Paste launch link', zh: '粘贴启动链接'),
  'pairing.action.scan': (en: 'Scan QR code', zh: '扫描二维码'),
  'pairing.scan.unavailable': (
    en: 'This device cannot scan QR codes. Paste the launch link instead.',
    zh: '此设备无法扫描二维码，请改为粘贴启动链接。',
  ),
  'pairing.paste.empty': (en: 'The clipboard has no text.', zh: '剪贴板里没有文字。'),
  'pairing.error.invalid': (
    en: 'That is not a launch link. Expected http://host:port/?token=…',
    zh: '这不是启动链接，格式应为 http://主机:端口/?token=…',
  ),
  'pairing.error.rejected': (
    en: 'The host refused the token. It may have restarted: start `dsh web` again and use the new link.',
    zh: '主机拒绝了令牌，可能已重启。请重新运行 `dsh web` 并使用新的链接。',
  ),
  'pairing.error.unreachable': (
    en: 'Could not reach the host. Check the address and that it is running.',
    zh: '无法连接主机，请检查地址以及主机是否在运行。',
  ),
  'pairing.error.unsupported': (
    en: 'This host runs dsh {version}, which this client has not been tested with.',
    zh: '该主机运行的 dsh {version} 未经此客户端测试。',
  ),
  'pairing.status.connecting': (en: 'Connecting…', zh: '正在连接…'),
  'pairing.status.reconnecting': (en: 'Reconnecting…', zh: '正在重新连接…'),
  'pairing.status.needsPairing': (
    en: 'The host restarted. Paste its new launch link to reconnect.',
    zh: '主机已重启，请粘贴新的启动链接重新连接。',
  ),
  'pairing.disclaimer': (
    en: 'An unofficial third-party client for DeepSeek Harness.',
    zh: 'DeepSeek Harness 的非官方第三方客户端。',
  ),

  // QR scanning
  'pairing.scan.title': (en: 'Scan QR code', zh: '扫描二维码'),
  'pairing.scan.hint': (
    en: 'Point the camera at a QR code of the launch link that `dsh web` prints.',
    zh: '将相机对准 `dsh web` 打印的启动链接的二维码。',
  ),
  'pairing.scan.notLink': (
    en: 'That QR code is not a dsh launch link. Try another one.',
    zh: '这个二维码不是 dsh 启动链接，请换一个。',
  ),
  'pairing.scan.denied': (
    en: 'Camera access is off. Allow it in the system settings, or paste the launch link instead.',
    zh: '相机权限已关闭。请在系统设置中允许，或改为粘贴启动链接。',
  ),
  'pairing.scan.openSettings': (en: 'Open settings', zh: '打开设置'),
  'pairing.scan.failed': (
    en: 'The camera could not start. Paste the launch link instead.',
    zh: '相机无法启动，请改为粘贴启动链接。',
  ),
  'pairing.scan.close': (en: 'Close', zh: '关闭'),

  // transport security
  'pairing.error.insecure': (
    en: 'Plain http is only allowed for this device and private networks, and {host} is neither. Use an https address.',
    zh: '明文 http 只允许用于本机和私有网络，而 {host} 两者都不是，请使用 https 地址。',
  ),
  'pairing.error.certificate': (
    en: 'The host\'s certificate was not accepted.',
    zh: '主机的证书未被接受。',
  ),
  'pairing.http.notice': (
    en: 'Plain http: not encrypted. Anyone on this network can read what you send. Use it only on a network you trust.',
    zh: '明文 http：未加密。同一网络中的人可以看到你发送的内容，请仅在可信网络中使用。',
  ),
  'security.encrypted': (en: 'Encrypted', zh: '已加密'),
  'security.pinned': (en: 'Encrypted, trusted certificate', zh: '已加密，证书已信任'),
  'security.plain': (en: 'Not encrypted', zh: '未加密'),
  'security.plain.detail': (
    en: 'Plain http. Traffic to this host is not encrypted.',
    zh: '明文 http，与此主机之间的通信未加密。',
  ),
  'cert.trust.title': (en: 'Trust this certificate?', zh: '信任此证书？'),
  'cert.trust.body': (
    en: 'The host at {host} uses a certificate that no authority has signed. If you set it up yourself, compare the fingerprint below with the one on the host. If they match, trust it: Whalee will then talk only to this exact certificate. Nothing has been sent to the host yet.',
    zh: '{host} 使用的证书没有任何机构签发。如果是你自己配置的，请把下面的指纹与主机上的指纹对比；一致就选择信任，之后 Whalee 只与这一张证书通信。目前还没有向主机发送任何内容。',
  ),
  'cert.fingerprint': (en: 'SHA-256 fingerprint', zh: 'SHA-256 指纹'),
  'cert.subject': (en: 'Issued to', zh: '颁发给'),
  'cert.validUntil': (en: 'Valid until {date}', zh: '有效期至 {date}'),
  'cert.expired': (en: 'Expired on {date}', zh: '已于 {date} 过期'),
  'cert.notYetValid': (en: 'Not valid before {date}', zh: '{date} 之前无效'),
  'cert.compareHint': (
    en: 'On the host: openssl x509 -in <certificate file> -noout -fingerprint -sha256',
    zh: '在主机上执行：openssl x509 -in <证书文件> -noout -fingerprint -sha256',
  ),
  'cert.trust.action': (en: 'Trust and connect', zh: '信任并连接'),
  'cert.cancel': (en: 'Cancel', zh: '取消'),
  'cert.changed.title': (en: 'The host\'s certificate changed', zh: '主机的证书已更改'),
  'cert.changed.body': (
    en: 'The certificate of {host} is not the one you trusted before. The host\'s owner may have replaced it, but it can also mean someone is intercepting the connection. Whalee sent nothing. Continue only if you know why it changed.',
    zh: '{host} 的证书与你之前信任的不是同一张。可能是主机所有者更换了证书，也可能有人在拦截连接。Whalee 没有发送任何内容。只有在你清楚原因时才继续。',
  ),
  'cert.changed.before': (en: 'Trusted before', zh: '之前信任的'),
  'cert.changed.now': (en: 'Presented now', zh: '现在出示的'),
  'cert.changed.review': (en: 'Review the new certificate', zh: '查看新证书'),
  'cert.forget': (en: 'Forget certificate', zh: '忘记证书'),
  'cert.settings.description': (
    en: 'Whalee trusts one certificate for this host (SHA-256 {fingerprint}).',
    zh: 'Whalee 只信任此主机的一张证书（SHA-256 {fingerprint}）。',
  ),

  // connection state
  'connection.retry': (
    en: 'Retry {n}, in {seconds}s',
    zh: '第 {n} 次重试，{seconds} 秒后',
  ),
  'connection.retrying': (en: 'Retry {n}', zh: '第 {n} 次重试'),
  'connection.unreachable.title': (en: 'Can\'t reach the host', zh: '连不上主机'),
  'connection.unreachable.body': (
    en: 'The host does not answer. Check that `dsh web` is running and that this device can reach {host}. Whalee keeps trying.',
    zh: '主机没有响应。请确认 `dsh web` 在运行，并且这台设备能访问 {host}。Whalee 会继续重试。',
  ),
  'connection.retryNow': (en: 'Retry now', zh: '立即重试'),
  'connection.needsPairing.title': (en: 'The host restarted', zh: '主机已重启'),
  'connection.needsPairing.body': (
    en: 'The launch link changes every time the host restarts. Scan or paste the new link to continue. Your open sessions and unsent messages stay as they are.',
    zh: '主机每次重启，启动链接都会变化。请扫描或粘贴新的链接继续使用，已打开的会话和未发送的消息都会保留。',
  ),
  'connection.repair': (en: 'Pair again', zh: '重新配对'),
  'connection.repair.title': (en: 'Pair again', zh: '重新配对'),
  'connection.certificate.title': (
    en: 'The connection was refused',
    zh: '连接被拒绝',
  ),
  'connection.certificate.body': (
    en: 'The host shows a different certificate than the one you trusted. Whalee stopped before sending anything.',
    zh: '主机出示的证书与你信任的不同，Whalee 在发送任何内容之前已停止。',
  ),
  'connection.certificate.review': (en: 'Review', zh: '查看'),
  'pairing.saved.unreachable': (en: 'Can\'t reach {host}', zh: '连不上 {host}'),
  'pairing.saved.tryAgain': (en: 'Try again', zh: '再试一次'),
  'pairing.saved.forget': (en: 'Forget this host', zh: '忘记此主机'),

  // session list
  'sessions.title': (en: 'Sessions', zh: '会话'),
  'panel.unavailable.title': (en: 'Not available yet', zh: '暂不可用'),
  'panel.unavailable.body': (
    en: '{name} is not part of Whalee yet. Use dsh web for it.',
    zh: 'Whalee 暂时还没有“{name}”，请先在 dsh web 中使用。',
  ),
  'sessions.empty.title': (en: 'No sessions yet', zh: '还没有会话'),
  'sessions.empty.body': (
    en: 'Start a new session to chat with your agent.',
    zh: '新建一个会话，开始和智能体对话。',
  ),
  'sessions.new': (en: 'New session', zh: '新建会话'),
  'sessions.untitled': (en: 'Untitled session', zh: '未命名会话'),
  'sessions.running': (en: 'Running', zh: '运行中'),
  'sessions.unavailable': (en: 'Unavailable', zh: '不可用'),
  'sessions.loadFailed': (en: 'Could not load sessions', zh: '无法加载会话'),
  'sessions.disconnect': (en: 'Disconnect', zh: '断开连接'),
  'sessions.refresh': (en: 'Refresh', zh: '刷新'),
  'sessions.createFailed': (en: 'Could not create a session', zh: '无法创建会话'),

  // session view
  'session.composer.placeholder': (en: 'Message', zh: '发送消息'),
  'session.composer.send': (en: 'Send', zh: '发送'),
  'session.composer.sendFailed': (en: 'The message was not sent', zh: '消息未能发送'),
  'attach.title': (en: 'Add attachment', zh: '添加附件'),
  'attach.photos': (en: 'Photo library', zh: '相册'),
  'attach.camera': (en: 'Take a photo', zh: '拍照'),
  'attach.files': (en: 'Files', zh: '文件'),
  'attach.pickFailed': (en: 'Could not read that file', zh: '无法读取该文件'),
  'attach.uploadsPending': (
    en: 'Wait for the files to finish uploading',
    zh: '请等待文件上传完成',
  ),
  'file.open': (en: 'Open', zh: '打开'),
  'file.save': (en: 'Save a copy', zh: '保存副本'),
  'file.downloading': (en: 'Downloading… {percent}%', zh: '正在下载… {percent}%'),
  'file.downloadFailed': (
    en: 'Could not download the file: {message}',
    zh: '无法下载文件：{message}',
  ),
  'file.cannotOpen': (
    en: 'No app on this device can open the file',
    zh: '此设备上没有可以打开该文件的应用',
  ),
  'attachment.position': (en: '{index} / {total}', zh: '{index} / {total}'),
  'session.cancel': (en: 'Stop', zh: '停止'),
  'session.model.unknown': (en: 'Model not set', zh: '未选择模型'),
  'session.loading': (en: 'Opening session…', zh: '正在打开会话…'),
  'session.openFailed': (en: 'Could not open this session', zh: '无法打开此会话'),
  'session.empty': (en: 'Say something to start.', zh: '说点什么开始吧。'),
  'session.removed': (en: 'This session was removed.', zh: '此会话已被移除。'),
  'session.reasoning': (en: 'Reasoning', zh: '推理过程'),
  'session.reasoning.running': (en: 'Thinking…', zh: '思考中…'),
  'session.tool.args': (en: 'Arguments', zh: '参数'),
  'session.tool.result': (en: 'Result', zh: '结果'),
  'session.tool.error': (en: 'Error', zh: '错误'),
  'session.tool.noResult': (en: 'Waiting for the result…', zh: '等待结果…'),
  'session.tool.preparing': (en: 'Preparing', zh: '准备中'),
  'session.tool.interrupted': (en: 'Interrupted', zh: '已中断'),
  'session.turn.stopped': (en: 'Stopped', zh: '已停止'),
  'session.turn.failed': (en: 'This turn failed', zh: '本轮运行失败'),
  'session.turn.maxTokens': (
    en: 'The answer was cut at the output limit.',
    zh: '回答达到输出长度上限被截断。',
  ),
  'session.turn.signedOut': (
    en: 'Stopped because the account was signed out.',
    zh: '账号已退出，任务已停止。',
  ),
  'session.turn.interrupted': (
    en: 'The host stopped before this turn finished.',
    zh: '主机在本轮完成前已退出。',
  ),
  'session.agentError': (en: 'Agent error', zh: '智能体错误'),
  'session.loadOlder': (en: 'Load earlier', zh: '加载更早'),

  // questions
  'question.submit': (en: 'Send answers', zh: '发送回答'),
  'question.other': (en: 'Other…', zh: '其他…'),
  'question.select.multiple': (en: 'Choose any', zh: '可多选'),
  'question.select.single': (en: 'Choose one', zh: '单选'),
  'question.waiting': (en: 'Your agent has a question', zh: '智能体有问题要问你'),
  'question.progress': (
    en: 'Question {index} of {count}',
    zh: '第 {index} / {count} 题',
  ),

  // settings (rows Whalee adds to dsh's General section)
  'settings.language.en': (en: 'English', zh: 'English'),
  'settings.language.zh': (en: '中文', zh: '中文'),
  'settings.language.description': (
    en: 'The language of the interface, shared with the host',
    zh: '界面语言，与主机共用',
  ),
  'settings.notifications.title': (en: 'Notifications', zh: '通知'),
  'settings.notifications.description': (
    en: 'Notify me when a session needs an approval or an answer while Whalee is in the background',
    zh: 'Whalee 在后台时，会话需要审批或回答就通知我',
  ),
  'settings.notifications.denied': (
    en: 'Notifications are blocked for Whalee in the system settings',
    zh: '系统设置中已关闭 Whalee 的通知',
  ),
  'settings.notifications.undetermined': (
    en: 'Allow notifications when the system asks',
    zh: '系统询问时请允许通知',
  ),
  'settings.notifications.allow': (en: 'Allow', zh: '允许'),
  'settings.notifications.openSettings': (
    en: 'Open system settings',
    zh: '打开系统设置',
  ),
  'settings.notifications.switch': (
    en: 'Notify about approvals and questions',
    zh: '通知审批与提问',
  ),
  'settings.host.title': (en: 'Host', zh: '主机'),
  'settings.host.security': (en: 'Connection', zh: '连接方式'),
  'settings.plugins.nav': (en: 'Plugins', zh: '插件'),

  // notifications
  'notice.approval.title': (en: 'Approval needed', zh: '需要审批'),
  'notice.approval.body': (en: '{session}: {tool}', zh: '{session}：{tool}'),
  'notice.question.title': (en: 'Your agent has a question', zh: '智能体有问题要问你'),
  'notice.question.body': (
    en: '{session}: {question}',
    zh: '{session}：{question}',
  ),
  'notice.channel.pending': (en: 'Approvals and questions', zh: '审批与提问'),
  'notice.channel.pending.description': (
    en: 'A session is waiting for you',
    zh: '会话在等你处理',
  ),
  'notice.channel.watching': (en: 'Staying connected', zh: '保持连接'),
  'notice.channel.watching.description': (
    en: 'Shown while sessions run and the app is in the background',
    zh: '会话运行且应用在后台时显示',
  ),
  'notice.watching.title': (en: 'Watching your sessions', zh: '正在关注你的会话'),
  'notice.watching.body.one': (
    en: '1 session is running. Whalee keeps the connection open to notify you.',
    zh: '1 个会话正在运行，Whalee 保持连接以便通知你。',
  ),
  'notice.watching.body.other': (
    en: '{count} sessions are running. Whalee keeps the connection open to notify you.',
    zh: '{count} 个会话正在运行，Whalee 保持连接以便通知你。',
  ),

  // time
  'time.justNow': (en: 'Just now', zh: '刚刚'),
  'time.minutes': (en: '{n} min ago', zh: '{n} 分钟前'),
  'time.hours': (en: '{n} h ago', zh: '{n} 小时前'),
  'time.days': (en: '{n} d ago', zh: '{n} 天前'),
};
