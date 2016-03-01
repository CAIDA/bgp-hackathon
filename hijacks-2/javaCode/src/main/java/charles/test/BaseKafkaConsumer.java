package charles.test;

import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.Set;

import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.PartitionInfo;
import org.apache.kafka.common.TopicPartition;

public abstract class BaseKafkaConsumer
{
    public final static String localCluster = "comet-17-22.sdsc.edu:9092";
    
    public KafkaConsumer<String, String> getConsumer()
    {
	Properties consumerProperties = new Properties();
	consumerProperties.put("bootstrap.servers", getConsumerHost());
	consumerProperties.put("group.id", getClass().getName() + "-" + Math.random());
	consumerProperties.put("enable.auto.commit", "false");
	consumerProperties.put("auto.commit.interval.ms", "1000");
	consumerProperties.put("session.timeout.ms", "30000");
	consumerProperties.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
	consumerProperties.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
	KafkaConsumer<String, String> consumer = new KafkaConsumer<String, String>(consumerProperties);

	return consumer;
    }

    public abstract String getConsumerHost();

    public abstract boolean isValidTopic(String topic);
    
    public abstract String getDestinationTopic(String topic);
    
    public boolean isStartAtBeginning()
    {
	return true;
    }

    public Map<String, List<PartitionInfo>> getTopicList()
    {
	Map<String, List<PartitionInfo>> topics = new HashMap<>(getConsumer().listTopics());

	Set<String> badTopics = new HashSet<>();
	for (String topic : topics.keySet())
	{
	    if (!isValidTopic(topic))
		badTopics.add(topic);
	}
	for (String badTopic : badTopics)
	{
	    topics.remove(badTopic);
	}
	return topics;
    }

    public abstract String evaluateRecord(String record);

    public abstract void evaluateRecords(ConsumerRecords<String, String> records, String destinationTopic);

    public Runnable getRunnable(final String sourceTopic, final int partition, final boolean startAtBeginning, final String destinationTopic)
    {
	return new Runnable()
	{
	    @Override
	    public void run()
	    {
		KafkaConsumer<String, String> consumer = getConsumer();

		TopicPartition topicPartition = new TopicPartition(sourceTopic, partition);
		consumer.assign(Arrays.asList(topicPartition));
		if (startAtBeginning)
		    consumer.seekToBeginning(topicPartition);

		while (true)
		{
		    ConsumerRecords<String, String> records = consumer.poll(100);

		    evaluateRecords(records, destinationTopic);

		    consumer.committed(topicPartition);
		    if (records.count() == 0)
		    {
			try
			{
			    Thread.sleep(10000);
			} catch (InterruptedException e)
			{
			    throw new IllegalStateException(e);
			}
		    }
		}
	    }
	};
    }

    public void start(final String sourceTopic, final int partition, final boolean startAtBeginning, final String destinationTopic)
    {
	Thread thread = new Thread(getRunnable(sourceTopic, partition, startAtBeginning, destinationTopic));
	thread.start();
    }

    public void startAllTopics()
    {
	Map<String, List<PartitionInfo>> topics = getTopicList();
	
	for(String topic : topics.keySet())
	{
	    for (PartitionInfo partitionInfo : topics.get(topic))
	    {
		start(topic, partitionInfo.partition(), isStartAtBeginning(), getDestinationTopic(topic));
	    }
	}
    }
}
