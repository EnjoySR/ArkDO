export interface PushRefreshStart {
  shouldStart: boolean;
  sequence: number;
}

export function nextPushRefreshStart(currentSequence: number, inFlight: boolean): PushRefreshStart {
  if (inFlight) {
    return {
      shouldStart: false,
      sequence: currentSequence
    };
  }
  return {
    shouldStart: true,
    sequence: currentSequence + 1
  };
}
