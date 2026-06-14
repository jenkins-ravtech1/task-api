package com.course.tasksevents;

import com.amazonaws.services.lambda.runtime.events.SQSBatchResponse;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Unit tests for the SQS consumer's real logic — parsing, idempotency, and
 * partial-batch failure reporting — using a fake {@link Notifier} (no AWS, no
 * mocking framework). The {@link com.amazonaws.services.lambda.runtime.Context}
 * is passed as null; the handler tolerates that for logging.
 */
class HandlerTest {

    /** Records every notify() call so tests can assert on them. */
    private static final class RecordingNotifier implements Notifier {
        final List<String> messages = new ArrayList<>();

        @Override
        public void notify(String subject, String message) {
            messages.add(message);
        }
    }

    @Test
    void validMessagePublishesExactlyOnce() {
        RecordingNotifier notifier = new RecordingNotifier();
        Handler handler = new Handler(notifier);

        SQSBatchResponse response = handler.handleRequest(
                eventOf("{\"type\":\"TASK_CREATED\",\"taskId\":\"abc\",\"title\":\"Learn Docker\"}"),
                null);

        assertEquals(1, notifier.messages.size());
        assertTrue(notifier.messages.get(0).contains("abc"));
        assertTrue(notifier.messages.get(0).contains("Learn Docker"));
        assertTrue(response.getBatchItemFailures().isEmpty());
    }

    @Test
    void duplicateTaskIdNotifiesOnlyOnce() {
        RecordingNotifier notifier = new RecordingNotifier();
        Handler handler = new Handler(notifier);
        String body = "{\"taskId\":\"dup\",\"title\":\"x\"}";

        handler.handleRequest(eventOf(body, body), null);

        assertEquals(1, notifier.messages.size(), "idempotent: same taskId publishes once");
    }

    @Test
    void malformedMessageIsReportedAsBatchFailure() {
        RecordingNotifier notifier = new RecordingNotifier();
        Handler handler = new Handler(notifier);

        SQSBatchResponse response = handler.handleRequest(eventOf("this is not json"), null);

        assertEquals(1, response.getBatchItemFailures().size());
        assertEquals("m0", response.getBatchItemFailures().get(0).getItemIdentifier());
        assertTrue(notifier.messages.isEmpty());
    }

    @Test
    void missingTaskIdIsReportedAsBatchFailure() {
        RecordingNotifier notifier = new RecordingNotifier();
        Handler handler = new Handler(notifier);

        SQSBatchResponse response = handler.handleRequest(eventOf("{\"title\":\"no id\"}"), null);

        assertEquals(1, response.getBatchItemFailures().size());
        assertTrue(notifier.messages.isEmpty());
    }

    @Test
    void oneBadMessageDoesNotSinkTheGoodOnes() {
        RecordingNotifier notifier = new RecordingNotifier();
        Handler handler = new Handler(notifier);

        SQSBatchResponse response = handler.handleRequest(
                eventOf("{\"taskId\":\"ok\",\"title\":\"good\"}", "broken"),
                null);

        assertEquals(1, notifier.messages.size(), "the good message is still published");
        assertEquals(1, response.getBatchItemFailures().size(), "only the bad message is reported failed");
        assertEquals("m1", response.getBatchItemFailures().get(0).getItemIdentifier());
    }

    // --- helpers -------------------------------------------------------------

    private static SQSEvent eventOf(String... bodies) {
        List<SQSEvent.SQSMessage> records = new ArrayList<>();
        for (int i = 0; i < bodies.length; i++) {
            SQSEvent.SQSMessage message = new SQSEvent.SQSMessage();
            message.setMessageId("m" + i);
            message.setBody(bodies[i]);
            records.add(message);
        }
        SQSEvent event = new SQSEvent();
        event.setRecords(records);
        return event;
    }
}
