package ch.kisoft.bench;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Named;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.GetItemRequest;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Pattern;

@Named("benchHandler")
@ApplicationScoped
public class Handler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private static final String TABLE = System.getenv().getOrDefault("BENCH_TABLE", "BenchTable");
    private static final String RUNTIME = System.getenv().getOrDefault("BENCH_RUNTIME", "java-jvm");
    private static final Pattern UUID_PATTERN =
            Pattern.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$");

    private final DynamoDbClient ddb;

    public Handler(DynamoDbClient ddb) {
        this.ddb = ddb;
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        if (!(input.get("id") instanceof String id) || !UUID_PATTERN.matcher(id).matches()) {
            return Map.of("error", "id must be a valid UUID");
        }
        if (!(input.get("payload") instanceof String payload) || payload.isEmpty()) {
            return Map.of("error", "payload must be a non-empty string");
        }

        byte[] payloadBytes = payload.getBytes(StandardCharsets.UTF_8);
        int payloadSize = payloadBytes.length;
        String payloadHash = sha256Hex(payloadBytes);
        String processedAt = Instant.now().toString();

        Map<String, AttributeValue> item = new LinkedHashMap<>();
        item.put("id", AttributeValue.fromS(id));
        item.put("processedAt", AttributeValue.fromS(processedAt));
        item.put("payloadSize", AttributeValue.fromN(Integer.toString(payloadSize)));
        item.put("payloadHash", AttributeValue.fromS(payloadHash));
        item.put("runtime", AttributeValue.fromS(RUNTIME));

        ddb.putItem(PutItemRequest.builder().tableName(TABLE).item(item).build());

        var got = ddb.getItem(GetItemRequest.builder()
                .tableName(TABLE)
                .key(Map.of("id", AttributeValue.fromS(id)))
                .consistentRead(true)
                .build());

        var attrs = got.item();
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("id", attrs.get("id").s());
        response.put("processedAt", attrs.get("processedAt").s());
        response.put("payloadSize", Integer.parseInt(attrs.get("payloadSize").n()));
        response.put("payloadHash", attrs.get("payloadHash").s());
        response.put("runtime", attrs.get("runtime").s());
        return response;
    }

    private static String sha256Hex(byte[] data) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(md.digest(data));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 not available", e);
        }
    }
}
