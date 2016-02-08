package charles.test;

import java.util.Iterator;
import java.util.LinkedList;
import java.util.List;
import java.util.Properties;
import java.util.concurrent.Future;

import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.Producer;
import org.apache.kafka.clients.producer.ProducerRecord;

public abstract class BaseKafkaOperation extends BaseKafkaConsumer
{
    private KafkaProducer<String, String> producer = null;

    public BaseKafkaOperation()
    {
    }

    public KafkaProducer<String, String> getProducer()
    {
	if (producer == null)
	{
	    Properties producerProperties = new Properties();
	    producerProperties.put("bootstrap.servers", getProducerHost());
	    producerProperties.put("acks", "all");
	    producerProperties.put("retries", 0);
	    producerProperties.put("batch.size", 16384);
	    producerProperties.put("linger.ms", 1);
	    producerProperties.put("buffer.memory", 33554432);
	    producerProperties.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer");
	    producerProperties.put("value.serializer", "org.apache.kafka.common.serialization.StringSerializer");

	    producer = new KafkaProducer<>(producerProperties);
	}
	return producer;
    }

    public abstract String getProducerHost();

    public abstract String evaluateRecord(String record);

    @SuppressWarnings("rawtypes")
    public void evaluateRecords(ConsumerRecords<String, String> records, String destinationTopic)
    {
	List<Future> futures = new LinkedList<>();
	Producer<String, String> producer = getProducer();
	for (ConsumerRecord<String, String> record : records)
	{
	    String result = evaluateRecord(record.value());
	    if (result != null)
	    {
		ProducerRecord<String, String> newRecord = new ProducerRecord<String, String>(destinationTopic, 0, "",
			result);
		futures.add(producer.send(newRecord));
	    }
	}
	while (futures.size() > 0)
	{
	    Iterator<Future> futureIterator = futures.iterator();
	    while (futureIterator.hasNext())
	    {
		if (futureIterator.next().isDone())
		    futureIterator.remove();
	    }
	}
    }
}
