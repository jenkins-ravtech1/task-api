package com.course.tasksevents;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.SQSBatchResponse;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * AWS Lambda that consumes TASK_CREATED messages from the task-events SQS queue
 * and publishes a notification to SNS (PRD §9).
 *
 * <p>For each message it:
 * <ol>
 *   <li>parses the JSON body and logs a structured line with the {@code taskId};</li>
 *   <li>publishes an SNS notification (subject "Task created");</li>
 *   <li>is idempotent — handling the same {@code taskId} twice does not send a
 *       second notification (at-least-once delivery means duplicates happen);</li>
 *   <li>uses PARTIAL BATCH RESPONSE — a single bad message is reported as failed
 *       so only IT is retried/DLQ'd, not the whole batch.</li>
 * </ol>
 *
 * <p>AWS invokes this via the handler reference {@code com.course.tasksevents.Handler}.
 */
public class Handler implements RequestHandler<SQSEvent, SQSBatchResponse> {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private final Notifier notifier;

    // Idempotency guard: taskIds already handled by THIS (warm) Lambda instance.
    // A warm container is reused across invocations, so this catches the common
    // duplicate-delivery case. (Cross-instance idempotency would need a store
    // such as a DynamoDB conditional write — out of scope for the course.)
    private final Set<String> processed = ConcurrentHashMap.newKeySet();

    /** Production constructor: publish to the real SNS topic from env config. */
    public Handler() {
        this(SnsNotifier.fromEnv());
    }

    /** Test/explicit constructor: inject any {@link Notifier}. */
    Handler(Notifier notifier) {
        this.notifier = notifier;
    }

    @Override
    public SQSBatchResponse handleRequest(SQSEvent event, Context context) {
        List<SQSBatchResponse.BatchItemFailure> failures = new ArrayList<>();

        for (SQSEvent.SQSMessage message : event.getRecords()) {
            try {
                process(message, context);
            } catch (Exception e) {
                // Report ONLY this message as failed → just it is retried and
                // eventually sent to the DLQ; the rest of the batch still succeeds.
                log(context, "Failed to process message " + message.getMessageId() + ": " + e.getMessage());
                failures.add(SQSBatchResponse.BatchItemFailure.builder()
                        .withItemIdentifier(message.getMessageId())
                        .build());
            }
        }

        return SQSBatchResponse.builder()
                .withBatchItemFailures(failures)
                .build();
    }

    private void process(SQSEvent.SQSMessage message, Context context) throws Exception {
        JsonNode body = MAPPER.readTree(message.getBody());
        String taskId = text(body, "taskId");
        String title = text(body, "title");
        if (taskId == null || taskId.isBlank()) {
            throw new IllegalArgumentException("message has no taskId");
        }

        // Structured log line with the taskId. We log id + title, never the raw
        // message body.
        log(context, "{\"event\":\"TASK_CREATED\",\"taskId\":\"" + taskId + "\",\"title\":\"" + safe(title) + "\"}");

        // Idempotency: skip the side effect (publishing) for a taskId we've
        // already handled — but still log that we saw it.
        if (!processed.add(taskId)) {
            log(context, "Already processed taskId " + taskId + " — skipping duplicate notification");
            return;
        }

        notifier.notify("Task created",
                "A new task was created: \"" + safe(title) + "\" (id " + taskId + ")");
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node.get(field);
        return (value == null || value.isNull()) ? null : value.asText();
    }

    /** Neutralize quotes so a title can't break our hand-built JSON log line. */
    private static String safe(String s) {
        return s == null ? "" : s.replace("\"", "'");
    }

    private static void log(Context context, String message) {
        if (context != null && context.getLogger() != null) {
            context.getLogger().log(message);
        }
    }
}
