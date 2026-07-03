import localUnitTest from './LocalUnit.test';
import architectureSkeletonTest from './ArchitectureSkeleton.test';
import challengeDetectorTest from './ChallengeDetector.test';
import arkWebNetworkBridgeTest from './ArkWebNetworkBridge.test';
import topicServiceTest from './TopicService.test';
import authServiceTest from './AuthService.test';
import challengeEventBusTest from './ChallengeEventBus.test';
import appRoutesTest from './AppRoutes.test';
import challengeResolutionProbeTest from './ChallengeResolutionProbe.test';
import challengeCompletionDetectorTest from './ChallengeCompletionDetector.test';

export default function testsuite() {
  localUnitTest();
  architectureSkeletonTest();
  challengeDetectorTest();
  arkWebNetworkBridgeTest();
  topicServiceTest();
  authServiceTest();
  challengeEventBusTest();
  appRoutesTest();
  challengeResolutionProbeTest();
  challengeCompletionDetectorTest();
}
