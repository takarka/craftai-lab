import 'package:builder/features/course/domain/course_topic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Assistant progress uses visible order instead of legacy storage IDs',
    () {
      expect(CourseTopic.highestCompletedOrder([]), 0);
      expect(CourseTopic.highestCompletedOrder([1, 2, 10]), 3);
      expect(CourseTopic.highestCompletedOrder([1, 2, 10, 3]), 4);
      expect(CourseTopic.highestCompletedOrder([5]), 6);
      expect(CourseTopic.highestCompletedOrder([11]), 7);
      expect(CourseTopic.highestCompletedOrder([9]), 11);
      expect(CourseTopic.highestCompletedOrder([999]), 0);
    },
  );
}
