#!/bin/sh
/home/etrain72/apache-maven-3.3.9/bin/mvn clean install exec:java -Dexec.mainClass="charles.test.HijacksCheckingConsumerProducer"
