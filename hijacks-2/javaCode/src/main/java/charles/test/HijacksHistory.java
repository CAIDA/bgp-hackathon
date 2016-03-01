package charles.test;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

// This class would be much better if it kept the state of the internet and an assumed view of it from each AS
public class HijacksHistory
{
    final double threshold = .01;
    final int prefixThreshold = 8;
    final double suspiciousAsThreshold = .75;

    // map of prefix to map of as to time at AS
    private ConcurrentHashMap<Prefix, ConcurrentHashMap<String, Long>> prefixHostHistory = new ConcurrentHashMap<>();

    // map of thread to map of prefix to last announcement time
    private ConcurrentHashMap<Thread, ConcurrentHashMap<Prefix, Long>> lastAnnouncementTimeByThread = new ConcurrentHashMap<>();

    // map of thread to map of prefix to last announcement as
    private ConcurrentHashMap<Thread, ConcurrentHashMap<Prefix, String>> lastAnnouncementAsByThread = new ConcurrentHashMap<>();
    
    // a map of as to announced prefixes
    private Map<String, Set<Prefix>> asGuestHistory = new HashMap<>();

    private double maxObservedAsScore = 0;

    public boolean isSuspiciousAS(String AS)
    {
	Set<Prefix> prefixes;
	synchronized (asGuestHistory)
	{
	    prefixes = asGuestHistory.get(AS);
	}

	if (prefixes == null || prefixes.size() < 2)
	    return false; // trust the little guys... as long as they are little

	double conflictingAsScore = 0;

	synchronized (asGuestHistory)
	{
	    for (Prefix prefix : prefixes)
	    {
		Map<String, Long> prefixHosts = prefixHostHistory.get(prefix);

		if (prefixHosts == null)
		{
		    int steps = 32;
		    for (Entry<Prefix, ConcurrentHashMap<String, Long>> entry : prefixHostHistory.entrySet())
		    {
			if (entry.getKey().isSubset(prefix) && entry.getKey().prefix - prefix.prefix < steps)
			{
			    steps = entry.getKey().prefix - prefix.prefix;
			    prefixHosts = entry.getValue();
			}
		    }
		}

		if (prefixHosts == null)
		    continue; // why do I need this?

		conflictingAsScore += 1 - (1.0 / prefixHosts.size());
	    }

	    conflictingAsScore /= prefixes.size();
	}

	if (conflictingAsScore > maxObservedAsScore)
	    maxObservedAsScore = conflictingAsScore;
	//if(conflictingAsScore > .9 * maxObservedAsScore)
	//    System.out.println(AS + " got a suspicion score of " + conflictingAsScore + " (Max Score So Far: " + maxObservedAsScore + ")");

	return conflictingAsScore > suspiciousAsThreshold;
    }

    boolean isAnnouncementGood(Prefix prefix, String AS, long time)
    {
	if (prefix.prefix <= prefixThreshold)
	    return true; // we don't care about the defaultish routes

	synchronized (asGuestHistory)
	{
	    if (!asGuestHistory.containsKey(AS))
		asGuestHistory.put(AS, new HashSet<Prefix>());
	    asGuestHistory.get(AS).add(prefix);
	}

	ConcurrentHashMap<Prefix, Long> lastAnnouncement = lastAnnouncementTimeByThread.get(Thread.currentThread());
	if (lastAnnouncement == null)
	{
	    lastAnnouncement = new ConcurrentHashMap<>();
	    lastAnnouncementTimeByThread.put(Thread.currentThread(), lastAnnouncement);
	}
	
	Long lastTimeSeen = lastAnnouncement.get(prefix);
	if (lastTimeSeen == null)
	{
	    int steps = 32;
	    for (Entry<Prefix, Long> entry : lastAnnouncement.entrySet())
	    {
		if (entry.getKey().isSubset(prefix) && entry.getKey().prefix - prefix.prefix < steps)
		{
		    steps = entry.getKey().prefix - prefix.prefix;
		    lastTimeSeen = entry.getValue();
		}
	    }
	}
	lastAnnouncement.put(prefix, time);
	if (lastTimeSeen == null)
	    return true;
	time -= lastTimeSeen;
	
	ConcurrentHashMap<Prefix, String> lastASMap = lastAnnouncementAsByThread.get(Thread.currentThread());
	if(lastASMap == null)
	{
	    lastASMap = new ConcurrentHashMap<>();
	    lastAnnouncementAsByThread.put(Thread.currentThread(), lastASMap);
	}
	String lastTimeAS = lastASMap.get(prefix);
	lastASMap.put(prefix, AS);
	if(lastTimeAS == null)
	{
	    // new data is fine
	    return true;
	}

	if (!prefixHostHistory.containsKey(prefix))
	{
	    prefixHostHistory.put(prefix, new ConcurrentHashMap<String, Long>());
	}
	Long timeAtLastAS = prefixHostHistory.get(prefix).get(lastTimeAS);
	if (timeAtLastAS == null)
	    timeAtLastAS = (long) 0;
	timeAtLastAS += time;
	prefixHostHistory.get(prefix).put(AS, timeAtLastAS);

	Long timeAtCurrentAs = prefixHostHistory.get(prefix).get(AS);
	if(timeAtCurrentAs == null)
	    timeAtCurrentAs = 0L;
	
	double totalTime = 0;
	for (Entry<String, Long> entry : prefixHostHistory.get(prefix).entrySet())
	{
	    totalTime += entry.getValue();
	}

	return timeAtCurrentAs / totalTime < threshold;
    }

    public long getTotalTimeSum()
    {
	long totalTime = 0;
	for (Map<String, Long> map : prefixHostHistory.values())
	{
	    for (Entry<String, Long> entry : map.entrySet())
	    {
		totalTime += entry.getValue();
	    }
	}
	return totalTime;
    }
}
