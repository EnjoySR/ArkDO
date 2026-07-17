// Markdown 工具栏按钮的纯插入逻辑:给定当前文本 + 选区,算出应用某格式后的新文本与新选区。
// 与 UI 解耦(不碰 TextAreaController),便于单测;由 ComposerPage 拿结果去 setText + setTextSelection。

// 编辑器文本状态:text 全文,selectionStart/End 为选区(相等表示无选区、即光标位置)。
export interface EditState {
  text: string;
  selectionStart: number;
  selectionEnd: number;
}

// 规整选区:钳到 [0, len] 且 start<=end,避免上游给的越界/倒置值算错。
function normalize(state: EditState): EditState {
  const len: number = state.text.length;
  let start: number = state.selectionStart;
  let end: number = state.selectionEnd;
  if (start < 0) {
    start = 0;
  }
  if (end < 0) {
    end = 0;
  }
  if (start > len) {
    start = len;
  }
  if (end > len) {
    end = len;
  }
  if (start > end) {
    const tmp: number = start;
    start = end;
    end = tmp;
  }
  return { text: state.text, selectionStart: start, selectionEnd: end };
}

// 包裹型(粗体/斜体/行内代码/删除线):有选区则用 before/after 包住选中文本并保持选中;
// 无选区则插入 before+placeholder+after 并选中 placeholder,方便直接改写。
export function wrapSelection(input: EditState, before: string, after: string, placeholder: string): EditState {
  const state: EditState = normalize(input);
  const start: number = state.selectionStart;
  const end: number = state.selectionEnd;
  const head: string = state.text.substring(0, start);
  const tail: string = state.text.substring(end);

  if (start === end) {
    const text: string = head + before + placeholder + after + tail;
    const selStart: number = start + before.length;
    return { text: text, selectionStart: selStart, selectionEnd: selStart + placeholder.length };
  }
  const selected: string = state.text.substring(start, end);
  const text: string = head + before + selected + after + tail;
  return { text: text, selectionStart: start + before.length, selectionEnd: end + before.length };
}

// 行首前缀型(引用/列表/标题):对选区覆盖到的每一行行首加 prefix。ordered=true 时前缀带递增序号。
// 无选区时作用于光标所在行。加完后选中被影响的整段,方便继续操作。
export function applyLinePrefix(input: EditState, prefix: string, ordered: boolean): EditState {
  const state: EditState = normalize(input);
  const text: string = state.text;
  const hadSelection: boolean = state.selectionEnd > state.selectionStart;
  // 选区起点所在行的行首:向前找最近的换行。
  const lineStart: number = text.lastIndexOf('\n', state.selectionStart - 1) + 1;
  // 选区终点所在行的行尾:向后找最近的换行(没有则到末尾)。0 长选区时用 selectionStart。
  const searchFrom: number = hadSelection ? state.selectionEnd - 1 : state.selectionStart;
  const nextNl: number = text.indexOf('\n', searchFrom);
  const lineEnd: number = nextNl < 0 ? text.length : nextNl;

  const head: string = text.substring(0, lineStart);
  const block: string = text.substring(lineStart, lineEnd);
  const tail: string = text.substring(lineEnd);
  const lines: string[] = block.split('\n');
  const prefixed: string[] = lines.map((line: string, index: number) => {
    const actualPrefix: string = ordered ? `${index + 1}. ` : prefix;
    return actualPrefix + line;
  });
  const newBlock: string = prefixed.join('\n');
  const newText: string = head + newBlock + tail;
  // 无选区(仅光标):把光标落到当前行前缀之后,便于直接接着打字。否则整行(含「# 」前缀)被选中,
  // 用户一打字就替换掉前缀——「点了 # 打字后 # 消失、标题失效」的真凶。有选区时保持整块选中。
  if (!hadSelection) {
    const firstPrefixLen: number = ordered ? '1. '.length : prefix.length;
    const caret: number = lineStart + firstPrefixLen;
    return { text: newText, selectionStart: caret, selectionEnd: caret };
  }
  return { text: newText, selectionStart: lineStart, selectionEnd: lineStart + newBlock.length };
}

// 在光标/选区处插入一段文本(替换选中),光标落到插入内容末尾。用于图片 markdown、表情等直插场景。
export function insertText(input: EditState, snippet: string): EditState {
  const state: EditState = normalize(input);
  const head: string = state.text.substring(0, state.selectionStart);
  const tail: string = state.text.substring(state.selectionEnd);
  const text: string = head + snippet + tail;
  const caret: number = state.selectionStart + snippet.length;
  return { text: text, selectionStart: caret, selectionEnd: caret };
}

// 插入片段并把光标定位到片段内某偏移(如链接 [](url) 把光标放进 () 里)。
// selectLength>0 时从该偏移起选中 selectLength 个字符(如选中占位文字)。
export function insertWithCursor(input: EditState, snippet: string, cursorOffset: number, selectLength: number): EditState {
  const state: EditState = normalize(input);
  const head: string = state.text.substring(0, state.selectionStart);
  const tail: string = state.text.substring(state.selectionEnd);
  const text: string = head + snippet + tail;
  const base: number = state.selectionStart + cursorOffset;
  return { text: text, selectionStart: base, selectionEnd: base + Math.max(0, selectLength) };
}

// 工具栏动作的种类:决定用上面哪个纯函数处理。
export enum MdActionKind {
  Wrap = 'wrap',
  LinePrefix = 'linePrefix',
  Insert = 'insert',
  InsertCursor = 'insertCursor'
}

// 一次工具栏格式动作的完整描述(各字段按 kind 取用)。由工具栏按钮携带、ComposerPage 统一 apply。
export interface MdAction {
  kind: MdActionKind;
  // Wrap 用:包裹标记与无选区时的占位。
  before?: string;
  after?: string;
  placeholder?: string;
  // LinePrefix 用:行首前缀;ordered=true 走递增序号。
  prefix?: string;
  ordered?: boolean;
  // Insert / InsertCursor 用:待插入片段;InsertCursor 额外用偏移与选中长度定位光标。
  snippet?: string;
  cursorOffset?: number;
  selectLength?: number;
}

// 按 action.kind 分发到对应纯函数,返回应用后的新状态。字段缺省时按空串/0 兜底。
export function applyAction(state: EditState, action: MdAction): EditState {
  switch (action.kind) {
    case MdActionKind.Wrap:
      return wrapSelection(state, action.before ? action.before : '', action.after ? action.after : '',
        action.placeholder ? action.placeholder : '');
    case MdActionKind.LinePrefix:
      return applyLinePrefix(state, action.prefix ? action.prefix : '', action.ordered === true);
    case MdActionKind.Insert:
      return insertText(state, action.snippet ? action.snippet : '');
    case MdActionKind.InsertCursor:
      return insertWithCursor(state, action.snippet ? action.snippet : '',
        action.cursorOffset ? action.cursorOffset : 0, action.selectLength ? action.selectLength : 0);
    default:
      return state;
  }
}
