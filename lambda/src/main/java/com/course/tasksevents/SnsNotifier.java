package com.course.tasksevents;

import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sns.SnsClient;

import java.net.URI;

/**
 * {@link Notifier} that publishes to an SNS topic — the real implementation used
 * when the Lambda runs in AWS (or against LocalStack).
 */
public class SnsNotifier implements Notifier {

    private final SnsClient sns;
    private final String topicArn;

    public SnsNotifier(SnsClient sns, String topicArn) {
        this.sns = sns;
        this.topicArn = topicArn;
    }

    /** Build from environment: NOTIFICATIONS_TOPIC_ARN, plus AWS_REGION /
     *  AWS_ENDPOINT_URL (the latter points the SDK at LocalStack locally). */
    public static SnsNotifier fromEnv() {
        var builder = SnsClient.builder();
        String region = System.getenv("AWS_REGION");
        if (region != null && !region.isBlank()) {
            builder.region(Region.of(region));
        }
        String endpoint = System.getenv("AWS_ENDPOINT_URL");
        if (endpoint != null && !endpoint.isBlank()) {
            builder.endpointOverride(URI.create(endpoint));
        }
        return new SnsNotifier(builder.build(), System.getenv("NOTIFICATIONS_TOPIC_ARN"));
    }

    @Override
    public void notify(String subject, String message) {
        sns.publish(b -> b.topicArn(topicArn).subject(subject).message(message));
    }
}
