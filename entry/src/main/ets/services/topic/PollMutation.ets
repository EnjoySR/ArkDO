import { Poll, PollOption, PollVoteResult } from '../../models/TopicDetail';

// 投票/撤销的本地乐观更新前快照,用于失败回滚。
export interface PollSnapshot {
  options: PollOption[];
  voters: number;
  chosenOptionIds: string[];
  canVote: boolean;
}

// 投票的本地乐观更新逻辑,独立成纯逻辑便于单测。
// 直接改 @Observed 的 Poll 字段 → 对应 PollView(@ObjectLink)精准重渲染。
export class PollMutation {
  static snapshot(poll: Poll): PollSnapshot {
    return {
      options: PollMutation.cloneOptions(poll.options),
      voters: poll.voters,
      chosenOptionIds: poll.chosenOptionIds.slice(),
      canVote: poll.canVote
    };
  }

  static restore(poll: Poll, snap: PollSnapshot): void {
    poll.options = PollMutation.cloneOptions(snap.options);
    poll.voters = snap.voters;
    poll.chosenOptionIds = snap.chosenOptionIds.slice();
    poll.canVote = snap.canVote;
  }

  // 乐观投票:按新旧已投项差异增减各选项票数;从未投→已投时投票人数 +1。
  static applyVote(poll: Poll, optionIds: string[]): void {
    const previous: string[] = poll.chosenOptionIds;
    const wasEmpty: boolean = previous.length === 0;
    const options: PollOption[] = PollMutation.cloneOptions(poll.options);

    // 取消不再选中的旧项。
    for (let index: number = 0; index < previous.length; index++) {
      if (optionIds.indexOf(previous[index]) < 0) {
        PollMutation.addVotes(options, previous[index], -1);
      }
    }
    // 新增本次选中的新项。
    for (let index: number = 0; index < optionIds.length; index++) {
      if (previous.indexOf(optionIds[index]) < 0) {
        PollMutation.addVotes(options, optionIds[index], 1);
      }
    }

    poll.options = options;
    poll.chosenOptionIds = optionIds.slice();
    if (wasEmpty && optionIds.length > 0) {
      poll.voters = poll.voters + 1;
    } else if (!wasEmpty && optionIds.length === 0) {
      poll.voters = Math.max(0, poll.voters - 1);
    }
    poll.canVote = poll.chosenOptionIds.length === 0;
  }

  // 乐观撤销:已投各项票数 -1、投票人数 -1、清空已投项。
  static applyRemove(poll: Poll): void {
    const previous: string[] = poll.chosenOptionIds;
    if (previous.length === 0) {
      return;
    }
    const options: PollOption[] = PollMutation.cloneOptions(poll.options);
    for (let index: number = 0; index < previous.length; index++) {
      PollMutation.addVotes(options, previous[index], -1);
    }
    poll.options = options;
    poll.chosenOptionIds = [];
    poll.voters = Math.max(0, poll.voters - 1);
    poll.canVote = true;
  }

  // 用服务端返回的真实值校正:按选项 id 覆盖票数,覆盖投票人数与已投项。
  static applyServerResult(poll: Poll, result: PollVoteResult): void {
    if (result.options.length > 0) {
      const merged: PollOption[] = PollMutation.cloneOptions(poll.options);
      for (let index: number = 0; index < result.options.length; index++) {
        const serverOption: PollOption = result.options[index];
        let matched: boolean = false;
        for (let inner: number = 0; inner < merged.length; inner++) {
          if (merged[inner].id === serverOption.id) {
            merged[inner] = { id: serverOption.id, label: merged[inner].label, votes: serverOption.votes };
            matched = true;
            break;
          }
        }
        if (!matched) {
          merged.push({ id: serverOption.id, label: serverOption.label, votes: serverOption.votes });
        }
      }
      poll.options = merged;
    }
    poll.voters = result.voters;
    poll.chosenOptionIds = result.chosenOptionIds.slice();
    poll.canVote = poll.chosenOptionIds.length === 0;
  }

  private static cloneOptions(source: PollOption[]): PollOption[] {
    const copy: PollOption[] = [];
    for (let index: number = 0; index < source.length; index++) {
      copy.push({ id: source[index].id, label: source[index].label, votes: source[index].votes });
    }
    return copy;
  }

  private static addVotes(options: PollOption[], optionId: string, delta: number): void {
    for (let index: number = 0; index < options.length; index++) {
      if (options[index].id === optionId) {
        options[index] = {
          id: options[index].id,
          label: options[index].label,
          votes: Math.max(0, options[index].votes + delta)
        };
        return;
      }
    }
  }
}
