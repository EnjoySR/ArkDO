import { Poll, PollOption, PollVoteResult } from '../../models/TopicDetail';
import { FaIconDefinition, FaIconView, getFaIcon } from './FaIcon';

// 已投项进度条填充:品牌蓝(强调色,明暗一致),保留字面量。
const BAR_FILL_CHOSEN: string = '#2563EB';
// 卡片与按钮圆角(调小,不要太圆润)。
const CARD_RADIUS: number = 4;
const BUTTON_RADIUS: number = 4;

// discourse-poll:一个投票的可交互卡片。两态:vote(选项圈,可投/已投) 与 results(百分比进度条)。
// 显示的可变数据(已投项 chosen / 投票人数 voters / 各选项票数 votes)都由本组件 @State 承载:
// 深层嵌套下 @ObjectLink 对 poll 深层字段变更重渲染不可靠,故点击时同步乐观改 @State(必定重渲染),
// 请求回来再用服务端真实值(PollVoteResult)校正;失败回滚。poll 仅作静态骨架(标题/选项 id/标签)与初值来源。
@Component
export struct PollView {
  @ObjectLink poll: Poll;
  // 投票:regular 传单个,multiple 传选中集合。返回服务端校正结果;null=失败(供本组件回滚)。
  onVote: (poll: Poll, optionIds: string[]) => Promise<PollVoteResult | null> = () => Promise.resolve(null);
  // 撤销投票。返回服务端校正结果;null=失败。
  onRemoveVote: (poll: Poll) => Promise<PollVoteResult | null> = () => Promise.resolve(null);
  @State private showResults: boolean = false;
  // 多选提交前的本地选中集合(regular 点击即投,不用此字段)。
  @State private pending: string[] = [];
  // 已投项。
  @State private chosen: string[] = [];
  // 投票人数。
  @State private voters: number = 0;
  // 各选项票数,下标与 poll.options 对齐。
  @State private votes: number[] = [];

  aboutToAppear(): void {
    this.syncFromPoll();
  }

  private syncFromPoll(): void {
    this.chosen = this.poll.chosenOptionIds.slice();
    this.voters = this.poll.voters;
    const votes: number[] = [];
    for (let index: number = 0; index < this.poll.options.length; index++) {
      votes.push(this.poll.options[index].votes);
    }
    this.votes = votes;
  }

  build() {
    Column() {
      if (this.poll.title && this.poll.title.length > 0) {
        Text(this.poll.title)
          .fontSize(16)
          .fontWeight(FontWeight.Normal)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Divider()
          .strokeWidth(1)
          .color($r('app.color.border'))
          .margin({ top: 12 })
      }

      if (this.showResults) {
        this.ResultsList()
        Divider().strokeWidth(1).color($r('app.color.border')).margin({ top: 4 })
        this.ResultsFooter()
      } else {
        this.OptionsList()
        Divider().strokeWidth(1).color($r('app.color.border')).margin({ top: 4 })
        this.InfoRow()
        this.ButtonsRow()
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .border({ width: 1, color: $r('app.color.border') })
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // ---- 投票态:选项圈 ----
  @Builder
  private OptionsList() {
    Column() {
      ForEach(this.poll.options, (option: PollOption, index: number) => {
        Row() {
          this.OptionCircle(option.id)
          Text(option.label)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .margin({ left: 12 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ top: 9, bottom: 9 })
        .onClick(() => {
          this.onOptionTap(option.id);
        })
      }, (option: PollOption, index: number) => `${index}-${option.id}`)
    }
    .width('100%')
    .margin({ top: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private OptionCircle(optionId: string) {
    if (this.isMarked(optionId)) {
      Circle()
        .width(22)
        .height(22)
        .fill($r('app.color.text_primary'))
        .stroke($r('app.color.text_primary'))
        .strokeWidth(1.5)
    } else {
      Circle()
        .width(22)
        .height(22)
        .fill(Color.Transparent)
        .stroke($r('app.color.text_primary'))
        .strokeWidth(1.5)
    }
  }

  // ---- 结果态:百分比进度条 ----
  @Builder
  private ResultsList() {
    Column() {
      ForEach(this.poll.options, (option: PollOption, index: number) => {
        Column() {
          Row() {
            Text(option.label)
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .fontWeight(this.isChosen(option.id) ? FontWeight.Medium : FontWeight.Normal)
              .layoutWeight(1)
            Text(`${this.percentAt(index)}%`)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Text(` · ${this.votesAt(index)} 票`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')

          // 进度条:灰底 + 按占比宽度的填充(已投项高亮蓝)。
          Stack({ alignContent: Alignment.Start }) {
            Row().width('100%').height(8).backgroundColor($r('app.color.fill_subtle')).borderRadius(4)
            Row()
              .width(`${this.percentAt(index)}%`)
              .height(8)
              .backgroundColor(this.isChosen(option.id) ? BAR_FILL_CHOSEN : $r('app.color.text_tertiary'))
              .borderRadius(4)
          }
          .width('100%')
          .margin({ top: 6 })
        }
        .width('100%')
        .margin({ top: index > 0 ? 14 : 0 })
        .alignItems(HorizontalAlign.Start)
      }, (option: PollOption, index: number) => `${index}-${option.id}`)
    }
    .width('100%')
    .margin({ top: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  // ---- 信息行(投票态):公开/保密 | N 投票人 ----
  @Builder
  private InfoRow() {
    Row() {
      Row() {
        FaIconView({ icon: this.faIcon('eye'), color: $r('app.color.text_secondary'), iconSize: 15 })
          .margin({ right: 6 })
        Text(this.poll.isPublic ? '投票为公开。' : '投票为保密。')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      Divider()
        .vertical(true)
        .height(16)
        .color($r('app.color.border'))
        .margin({ left: 8, right: 8 })

      Text(`${this.voters} 投票人`)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  // ---- 按钮行(投票态):结果 [+ 撤消投票] ----
  @Builder
  private ButtonsRow() {
    Row() {
      if (this.canSeeResults()) {
        this.PollButton('chart-bar', '结果', false, () => {
          this.showResults = true;
        })
      }
      if (this.isVoted()) {
        if (this.canSeeResults()) {
          Blank().width(10)
        }
        this.PollButton('arrow-rotate-left', '撤消投票', true, () => {
          this.doRemove();
        })
      } else if (this.isMultiple() && this.pending.length > 0) {
        // 多选:选好后统一提交。
        Blank().width(10)
        this.PollButton('check', '投票', true, () => {
          this.doVote(this.pending.slice());
        })
      }
    }
    .width('100%')
    .margin({ top: 4 })
  }

  // ---- 底部(结果态):< 返回 | N 投票人 ----
  @Builder
  private ResultsFooter() {
    Row() {
      Row() {
        FaIconView({ icon: this.faIcon('angle-left'), color: $r('app.color.text_secondary'), iconSize: 16 })
          .margin({ right: 6 })
        Text('返回')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .border({ width: 1, color: $r('app.color.border') })
      .borderRadius(BUTTON_RADIUS)
      .onClick(() => {
        this.showResults = false;
      })

      Blank()

      Text(`${this.voters} 投票人`)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .margin({ top: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private PollButton(iconId: string, label: string, flexible: boolean, action: () => void) {
    Row() {
      FaIconView({ icon: this.faIcon(iconId), color: $r('app.color.text_secondary'), iconSize: 15 })
        .margin({ right: 6 })
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(flexible ? 1 : 0)
    .padding({ left: 16, right: 16, top: 9, bottom: 9 })
    .border({ width: 1, color: $r('app.color.border') })
    .borderRadius(BUTTON_RADIUS)
    .onClick(action)
  }

  // 点选项:regular 立即投票并切结果;multiple 切换本地选中。仅可投时生效。
  private onOptionTap(optionId: string): void {
    if (!this.isVotable()) {
      return;
    }
    if (this.isMultiple()) {
      this.pending = this.toggle(this.pending, optionId);
      return;
    }
    this.doVote([optionId]);
  }

  // 乐观投票:同步改本地 @State(必定重渲染),切到结果态;请求回来用服务端值校正,失败回滚。
  private doVote(optionIds: string[]): void {
    const prevChosen: string[] = this.chosen.slice();
    const prevVoters: number = this.voters;
    const prevVotes: number[] = this.votes.slice();

    const wasEmpty: boolean = this.chosen.length === 0;
    for (let index: number = 0; index < optionIds.length; index++) {
      if (this.chosen.indexOf(optionIds[index]) < 0) {
        this.bumpVote(optionIds[index], 1);
      }
    }
    for (let index: number = 0; index < prevChosen.length; index++) {
      if (optionIds.indexOf(prevChosen[index]) < 0) {
        this.bumpVote(prevChosen[index], -1);
      }
    }
    if (wasEmpty && optionIds.length > 0) {
      this.voters = this.voters + 1;
    }
    this.chosen = optionIds.slice();
    this.pending = [];
    this.showResults = true;

    this.onVote(this.poll, optionIds).then((result: PollVoteResult | null) => {
      if (result) {
        this.applyServer(result);
      } else {
        this.chosen = prevChosen;
        this.voters = prevVoters;
        this.votes = prevVotes;
        this.showResults = false;
      }
    });
  }

  // 乐观撤销:同步改本地 @State 回到未投票态;失败回滚。
  private doRemove(): void {
    const prevChosen: string[] = this.chosen.slice();
    const prevVoters: number = this.voters;
    const prevVotes: number[] = this.votes.slice();

    for (let index: number = 0; index < prevChosen.length; index++) {
      this.bumpVote(prevChosen[index], -1);
    }
    if (prevChosen.length > 0) {
      this.voters = Math.max(0, this.voters - 1);
    }
    this.chosen = [];
    this.pending = [];
    this.showResults = false;

    this.onRemoveVote(this.poll).then((result: PollVoteResult | null) => {
      if (result) {
        this.applyServer(result);
      } else {
        this.chosen = prevChosen;
        this.voters = prevVoters;
        this.votes = prevVotes;
      }
    });
  }

  // 用服务端真实值校正本地显示(吸收他人并发投票带来的偏差)。
  private applyServer(result: PollVoteResult): void {
    this.voters = result.voters;
    this.chosen = result.chosenOptionIds.slice();
    const votes: number[] = this.votes.slice();
    for (let index: number = 0; index < this.poll.options.length; index++) {
      const optionId: string = this.poll.options[index].id;
      for (let inner: number = 0; inner < result.options.length; inner++) {
        if (result.options[inner].id === optionId) {
          votes[index] = result.options[inner].votes;
          break;
        }
      }
    }
    this.votes = votes;
  }

  private bumpVote(optionId: string, delta: number): void {
    const votes: number[] = this.votes.slice();
    for (let index: number = 0; index < this.poll.options.length; index++) {
      if (this.poll.options[index].id === optionId) {
        const current: number = index < votes.length ? votes[index] : 0;
        votes[index] = Math.max(0, current + delta);
        this.votes = votes;
        return;
      }
    }
  }

  private toggle(list: string[], value: string): string[] {
    const next: string[] = [];
    let removed: boolean = false;
    for (let index: number = 0; index < list.length; index++) {
      if (list[index] === value) {
        removed = true;
        continue;
      }
      next.push(list[index]);
    }
    if (!removed) {
      next.push(value);
    }
    return next;
  }

  private isMultiple(): boolean {
    return this.poll.type === 'multiple';
  }

  private isVoted(): boolean {
    return this.chosen.length > 0;
  }

  // 可投票:投票未关闭且当前用户尚未投过。
  private isVotable(): boolean {
    return this.poll.status === 'open' && !this.isVoted();
  }

  // 选项圈是否点亮:已投看 chosen;多选未提交看本地 pending。
  private isMarked(optionId: string): boolean {
    if (this.isVoted()) {
      return this.isChosen(optionId);
    }
    return this.isMultiple() && this.pending.indexOf(optionId) >= 0;
  }

  private isChosen(optionId: string): boolean {
    return this.chosen.indexOf(optionId) >= 0;
  }

  // 能否查看结果:results=always、已投、或已关闭。
  private canSeeResults(): boolean {
    return this.poll.results === 'always' || this.isVoted() || this.poll.status === 'closed';
  }

  private votesAt(index: number): number {
    return index >= 0 && index < this.votes.length ? this.votes[index] : 0;
  }

  private totalVotes(): number {
    let total: number = 0;
    for (let index: number = 0; index < this.votes.length; index++) {
      total = total + this.votes[index];
    }
    return total;
  }

  private percentAt(index: number): number {
    const total: number = this.totalVotes();
    if (total <= 0) {
      return 0;
    }
    return Math.round((this.votesAt(index) / total) * 100);
  }

  private faIcon(name: string): FaIconDefinition {
    const def: FaIconDefinition | undefined = getFaIcon(name);
    return def ? def : { id: name, rawfilePath: '' };
  }
}
