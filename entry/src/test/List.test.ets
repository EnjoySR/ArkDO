import localUnitTest from './LocalUnit.test';
import architectureSkeletonTest from './ArchitectureSkeleton.test';
import challengeDetectorTest from './ChallengeDetector.test';

export default function testsuite() {
  localUnitTest();
  architectureSkeletonTest();
  challengeDetectorTest();
}
