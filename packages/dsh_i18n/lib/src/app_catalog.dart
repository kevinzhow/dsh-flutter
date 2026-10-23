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
    en: 'Camera scanning is not available yet. Paste the launch link instead.',
    zh: '暂不支持相机扫码，请改为粘贴启动链接。',
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

  // session list
  'sessions.title': (en: 'Sessions', zh: '会话'),
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

  // settings
  'settings.title': (en: 'Appearance and language', zh: '外观与语言'),
  'settings.theme.system': (en: 'System', zh: '跟随系统'),
  'settings.theme.light': (en: 'Light', zh: '浅色'),
  'settings.theme.dark': (en: 'Dark', zh: '深色'),
  'settings.language.en': (en: 'English', zh: 'English'),
  'settings.language.zh': (en: '中文', zh: '中文'),
  'settings.language': (en: 'Language', zh: '语言'),
  'settings.theme': (en: 'Theme', zh: '主题'),

  // time
  'time.justNow': (en: 'Just now', zh: '刚刚'),
  'time.minutes': (en: '{n} min ago', zh: '{n} 分钟前'),
  'time.hours': (en: '{n} h ago', zh: '{n} 小时前'),
  'time.days': (en: '{n} d ago', zh: '{n} 天前'),
};
