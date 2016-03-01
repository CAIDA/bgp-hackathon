package charles.test;

import java.util.Properties;
import java.util.concurrent.Future;

import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;

public class BaseKafkaProducer
{
    private KafkaProducer<String, String> producer = null;
    
    private String host;
    
    public BaseKafkaProducer(String host)
    {
	this.host = host;
    }
    
    public KafkaProducer<String, String> getProducer()
    {
	if (producer == null)
	{
	    Properties producerProperties = new Properties();
	    producerProperties.put("bootstrap.servers", host);
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
    
    public Future<RecordMetadata> send(String topic, String key, String message)
    {
	ProducerRecord<String, String> record = new ProducerRecord<String, String>(topic, 0, key, message);
	return getProducer().send(record);
    }
}
