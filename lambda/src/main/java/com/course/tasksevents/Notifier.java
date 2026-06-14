package com.course.tasksevents;

/**
 * Sends a notification somewhere. Hiding the actual delivery (SNS) behind this
 * tiny interface lets the {@link Handler} be unit-tested with a fake notifier —
 * no AWS, no mocking framework.
 */
@FunctionalInterface
public interface Notifier {
    void notify(String subject, String message);
}
