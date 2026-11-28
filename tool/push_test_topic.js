// Shared validator for Phase 6H test notification topics (ADR-059 / ADR-060).
// Kept in sync with `_testPushTopicRegex` in `lib/domain/push.dart` and `firestore.rules`.

export const TEST_TOPIC_RE = /^test_[a-z0-9_]{3,20}$/;

/**
 * Returns true if [topic] is a valid test push topic (`test_[a-z0-9_]{3,20}`).
 */
export function isValidTestTopic(topic) {
  return typeof topic === 'string' && TEST_TOPIC_RE.test(topic);
}
