package com.course.tasksapi.repo;

import com.course.tasksapi.config.Config;
import com.course.tasksapi.model.Task;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.DeleteItemResponse;
import software.amazon.awssdk.services.dynamodb.model.GetItemResponse;
import software.amazon.awssdk.services.dynamodb.model.ReturnValue;
import software.amazon.awssdk.services.dynamodb.model.ScanResponse;

import java.net.URI;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * DynamoDB-backed {@link TaskRepository} (PRD FR-6), used from session 5 onward
 * when {@code STORAGE=dynamodb}.
 *
 * <p>We use the LOW-LEVEL DynamoDB client and map a {@link Task} to/from a
 * {@code Map<String,AttributeValue>} by hand. That is a little more code than the
 * "enhanced" object mapper, but it shows exactly what a DynamoDB item looks like
 * and keeps the {@code Task} model free of database annotations.
 *
 * <p>The same code works against real AWS and against LocalStack: if
 * {@code AWS_ENDPOINT_URL} is set, the SDK is pointed at LocalStack.
 */
public class DynamoDbTaskRepository implements TaskRepository {

    private final DynamoDbClient client;
    private final String tableName;

    public DynamoDbTaskRepository(Config cfg) {
        var builder = DynamoDbClient.builder();
        if (cfg.awsRegion() != null) {
            builder.region(Region.of(cfg.awsRegion()));
        }
        // AWS_ENDPOINT_URL makes the SDK talk to LocalStack instead of real AWS.
        if (cfg.awsEndpointUrl() != null) {
            builder.endpointOverride(URI.create(cfg.awsEndpointUrl()));
        }
        this.client = builder.build();
        this.tableName = cfg.tasksTable();
    }

    /** Explicit-client constructor — used by integration tests. */
    public DynamoDbTaskRepository(DynamoDbClient client, String tableName) {
        this.client = client;
        this.tableName = tableName;
    }

    @Override
    public List<Task> findAll() {
        // A Scan reads the whole table. Fine for a small teaching table; a real
        // high-volume API would paginate or use a different access pattern.
        ScanResponse response = client.scan(b -> b.tableName(tableName));
        List<Task> tasks = new ArrayList<>();
        for (Map<String, AttributeValue> item : response.items()) {
            tasks.add(fromItem(item));
        }
        return tasks;
    }

    @Override
    public Optional<Task> findById(String id) {
        GetItemResponse response = client.getItem(b -> b.tableName(tableName).key(keyFor(id)));
        if (!response.hasItem() || response.item().isEmpty()) {
            return Optional.empty();
        }
        return Optional.of(fromItem(response.item()));
    }

    @Override
    public Task save(Task task) {
        client.putItem(b -> b.tableName(tableName).item(toItem(task)));
        return task;
    }

    @Override
    public boolean deleteById(String id) {
        // ALL_OLD returns the deleted item's attributes — empty if nothing was
        // there, which is how we know whether we actually deleted something.
        DeleteItemResponse response = client.deleteItem(b -> b
                .tableName(tableName)
                .key(keyFor(id))
                .returnValues(ReturnValue.ALL_OLD));
        return response.hasAttributes() && !response.attributes().isEmpty();
    }

    // --- mapping between Task and the DynamoDB item representation ------------

    private static Map<String, AttributeValue> keyFor(String id) {
        return Map.of("id", AttributeValue.fromS(id));
    }

    private static Map<String, AttributeValue> toItem(Task task) {
        Map<String, AttributeValue> item = new HashMap<>();
        item.put("id", AttributeValue.fromS(task.getId()));
        item.put("title", AttributeValue.fromS(task.getTitle()));
        if (task.getDescription() != null) {
            item.put("description", AttributeValue.fromS(task.getDescription()));
        }
        item.put("done", AttributeValue.fromBool(task.isDone()));
        item.put("createdAt", AttributeValue.fromS(task.getCreatedAt()));
        return item;
    }

    private static Task fromItem(Map<String, AttributeValue> item) {
        Task task = new Task();
        task.setId(item.get("id").s());
        task.setTitle(item.get("title").s());
        AttributeValue description = item.get("description");
        task.setDescription(description == null ? null : description.s());
        AttributeValue done = item.get("done");
        task.setDone(done != null && Boolean.TRUE.equals(done.bool()));
        task.setCreatedAt(item.get("createdAt").s());
        return task;
    }
}
