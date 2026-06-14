package com.course.tasksapi;

import com.course.tasksapi.events.SqsEventPublisher;
import com.course.tasksapi.model.Task;
import com.course.tasksapi.repo.DynamoDbTaskRepository;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.localstack.LocalStackContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeDefinition;
import software.amazon.awssdk.services.dynamodb.model.BillingMode;
import software.amazon.awssdk.services.dynamodb.model.KeySchemaElement;
import software.amazon.awssdk.services.dynamodb.model.KeyType;
import software.amazon.awssdk.services.dynamodb.model.ScalarAttributeType;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.Message;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Integration test (PRD §16): exercises the DynamoDB repository and the SQS
 * publisher against a REAL LocalStack started by Testcontainers — proving the
 * AWS SDK code works against the actual API surface, not a mock.
 *
 * <p>Named *IT so the Maven failsafe plugin runs it during `verify`.
 * {@code disabledWithoutDocker = true} makes the whole class SKIP cleanly when
 * Testcontainers can't reach a Docker daemon (e.g. some Docker Desktop setups),
 * instead of failing the build. CI's Linux Docker runs it for real.
 */
@Testcontainers(disabledWithoutDocker = true)
class DynamoSqsIT {

    private static final DockerImageName IMAGE = DockerImageName.parse("localstack/localstack:3");
    private static final String TABLE = "tasks";

    @Container
    static final LocalStackContainer LOCALSTACK = new LocalStackContainer(IMAGE)
            .withServices(LocalStackContainer.Service.DYNAMODB, LocalStackContainer.Service.SQS);

    static DynamoDbClient dynamo;
    static SqsClient sqs;
    static String queueUrl;

    @BeforeAll
    static void setUp() {
        var credentials = StaticCredentialsProvider.create(
                AwsBasicCredentials.create(LOCALSTACK.getAccessKey(), LOCALSTACK.getSecretKey()));
        var region = Region.of(LOCALSTACK.getRegion());
        var endpoint = LOCALSTACK.getEndpoint();

        dynamo = DynamoDbClient.builder()
                .endpointOverride(endpoint).region(region).credentialsProvider(credentials).build();
        sqs = SqsClient.builder()
                .endpointOverride(endpoint).region(region).credentialsProvider(credentials).build();

        dynamo.createTable(b -> b
                .tableName(TABLE)
                .attributeDefinitions(AttributeDefinition.builder()
                        .attributeName("id").attributeType(ScalarAttributeType.S).build())
                .keySchema(KeySchemaElement.builder()
                        .attributeName("id").keyType(KeyType.HASH).build())
                .billingMode(BillingMode.PAY_PER_REQUEST));
        dynamo.waiter().waitUntilTableExists(b -> b.tableName(TABLE));

        queueUrl = sqs.createQueue(b -> b.queueName("task-events")).queueUrl();
    }

    @Test
    void dynamoRepositoryPersistsAndReadsBack() {
        var repo = new DynamoDbTaskRepository(dynamo, TABLE);

        Task saved = repo.save(Task.create("persisted task", "with a description"));

        var found = repo.findById(saved.getId());
        assertTrue(found.isPresent());
        assertEquals("persisted task", found.get().getTitle());
        assertEquals("with a description", found.get().getDescription());
        assertFalse(found.get().isDone());

        assertTrue(repo.findAll().stream().anyMatch(t -> t.getId().equals(saved.getId())));

        assertTrue(repo.deleteById(saved.getId()));
        assertTrue(repo.findById(saved.getId()).isEmpty());
    }

    @Test
    void sqsPublisherEnqueuesExactlyOneTaskCreatedMessage() {
        var publisher = new SqsEventPublisher(sqs, queueUrl);
        Task task = Task.create("Learn Docker", null);

        publisher.taskCreated(task);

        List<Message> messages = sqs.receiveMessage(b -> b
                .queueUrl(queueUrl).maxNumberOfMessages(10).waitTimeSeconds(5)).messages();

        assertEquals(1, messages.size());
        String body = messages.get(0).body();
        assertTrue(body.contains("TASK_CREATED"), body);
        assertTrue(body.contains(task.getId()), body);
    }
}
