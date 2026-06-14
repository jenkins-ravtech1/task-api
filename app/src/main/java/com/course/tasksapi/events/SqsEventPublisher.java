package com.course.tasksapi.events;

import com.course.tasksapi.config.Config;
import com.course.tasksapi.model.Task;
import com.course.tasksapi.util.Json;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sqs.SqsClient;

import java.net.URI;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * SQS-backed {@link EventPublisher} (PRD FR-7, §9), used when
 * {@code TASK_EVENTS_QUEUE_URL} is set. On a successful create it puts ONE
 * {@code TASK_CREATED} message on the queue:
 *
 * <pre>
 *   { "type":"TASK_CREATED", "taskId":"...", "title":"...", "occurredAt":"..." }
 * </pre>
 *
 * <p>Publishing is best-effort: the caller ({@code TasksHandler}) wraps this in a
 * try/catch so a queue hiccup never fails the user's request (the task is already
 * saved).
 */
public class SqsEventPublisher implements EventPublisher {

    private final SqsClient client;
    private final String queueUrl;

    public SqsEventPublisher(Config cfg) {
        var builder = SqsClient.builder();
        if (cfg.awsRegion() != null) {
            builder.region(Region.of(cfg.awsRegion()));
        }
        if (cfg.awsEndpointUrl() != null) {
            builder.endpointOverride(URI.create(cfg.awsEndpointUrl()));
        }
        this.client = builder.build();
        this.queueUrl = cfg.taskEventsQueueUrl();
    }

    /** Explicit-client constructor — used by integration tests. */
    public SqsEventPublisher(SqsClient client, String queueUrl) {
        this.client = client;
        this.queueUrl = queueUrl;
    }

    @Override
    public void taskCreated(Task task) {
        Map<String, Object> message = new LinkedHashMap<>();
        message.put("type", "TASK_CREATED");
        message.put("taskId", task.getId());
        message.put("title", task.getTitle());
        message.put("occurredAt", Instant.now().truncatedTo(ChronoUnit.SECONDS).toString());

        String body = Json.toJson(message);
        client.sendMessage(b -> b.queueUrl(queueUrl).messageBody(body));
    }
}
