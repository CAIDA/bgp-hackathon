package charles.test;

public class CopyConsumerProducer extends BaseKafkaOperation
{
    public static void main(String[] args)
    {
	CopyConsumerProducer copier = new CopyConsumerProducer();
	
	copier.startAllTopics();
    }

    @Override
    public String getProducerHost()
    {
	return localCluster;
    }

    @Override
    public String evaluateRecord(String record)
    {
	return record;
    }

    @Override
    public String getConsumerHost()
    {
	return "comet-17-08.sdsc.edu:9092";
    }

    @Override
    public boolean isValidTopic(String topic)
    {
	return topic.matches("raw-rrc.*");
    }

    @Override
    public String getDestinationTopic(String topic)
    {
	return "cb_" + topic;
    }
}
