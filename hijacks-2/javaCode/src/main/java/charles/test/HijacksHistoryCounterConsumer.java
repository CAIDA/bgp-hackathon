package charles.test;

import java.util.Map.Entry;

import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

public class HijacksHistoryCounterConsumer extends BaseKafkaConsumer
{
    HijacksHistory history;

    public static long observedMessages = 0;
    public static long intermediateMessages = 0;
    public static long processedMessages = 0;

    public HijacksHistoryCounterConsumer(HijacksHistory history)
    {
	this.history = history;
    }

    @Override
    public String getConsumerHost()
    {
	return localCluster;
    }

    @Override
    public boolean isValidTopic(String topic)
    {
	return topic.matches("raw-rrc.*");
    }

    @Override
    public String getDestinationTopic(String topic)
    {
	return null;
    }

    @Override
    public String evaluateRecord(String record)
    {
	observedMessages++;
	try
	{
	    JsonElement element = new JsonParser().parse(record);

	    JsonObject bgpMessage = element.getAsJsonObject();

	    Double time = bgpMessage.get("time").getAsDouble();

	    if (!bgpMessage.has("neighbor"))
		return null;
	    JsonObject neighbors = bgpMessage.get("neighbor").getAsJsonObject();

	    JsonObject asn = neighbors.get("asn").getAsJsonObject();
	    String AS = asn.get("peer").getAsString();

	    intermediateMessages++;

	    if (!neighbors.has("message"))
		return null;
	    JsonObject message = neighbors.get("message").getAsJsonObject();

	    if (!message.has("update"))
		return null;
	    JsonObject update = message.get("update").getAsJsonObject();

	    // intermediateMessages++;

	    if (!update.has("announce"))
		return null;
	    JsonObject announce = update.get("announce").getAsJsonObject();

	    processedMessages++;

	    for (Entry<String, JsonElement> announceEntry : announce.entrySet())
	    {
		for (Entry<String, JsonElement> innerEntry : announceEntry.getValue().getAsJsonObject().entrySet())
		{
		    if ("null".equals(innerEntry.getKey()))
			continue;
		    for (Entry<String, JsonElement> prefixEntry : innerEntry.getValue().getAsJsonObject().entrySet())
		    {
			// if(!prefixEntry.getKey().matches(".+/.+"))
			// continue;
			history.isAnnouncementGood(new Prefix(prefixEntry.getKey()), AS, time.longValue());
		    }
		}
	    }
	} catch (ClassCastException | NullPointerException | IllegalStateException e)
	{
	    System.out.println("Can't parse: " + record);
	    e.printStackTrace();
	    System.exit(-1);
	}
	return null;
    }

    @Override
    public void evaluateRecords(ConsumerRecords<String, String> records, String destinationTopic)
    {
	for (ConsumerRecord<String, String> record : records)
	{
	    evaluateRecord(record.value());
	}
    }
}
