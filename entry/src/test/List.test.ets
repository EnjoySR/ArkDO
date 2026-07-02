import localUnitTest from './LocalUnit.test';
import architectureSkeletonTest from './ArchitectureSkeleton.test';

export default function testsuite() {
  localUnitTest();
  architectureSkeletonTest();
}
