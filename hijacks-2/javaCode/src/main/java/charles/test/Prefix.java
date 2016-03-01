package charles.test;

import java.net.InetAddress;
import java.net.UnknownHostException;

public class Prefix
{
    final public InetAddress base;
    final public int prefix;

    public Prefix(String prefixString)
    {
	String[] prefixParts = prefixString.split("/");
	try
	{
	    base = InetAddress.getByName(prefixParts[0]);
	} catch (UnknownHostException e)
	{
	    throw new IllegalStateException("Can't find host for: " + prefixString);
	}
	prefix = Integer.parseInt(prefixParts[1]);
    }
    
    boolean isSubset(Prefix other)
    {
	if(this.equals(other))
	    return true;// I am a subset of myself
	
	byte[] myAddress = base.getAddress();
	byte[] otherAddress = other.base.getAddress();
	
	// make sure they are both ipv4 or ipv6
	if(myAddress.length != otherAddress.length)
	    return false;
	
	// other must be more specific than this in order to be a subset
	if(prefix >= other.prefix)
	    return false;
	
	int partialByte = prefix / 8;
	int remainingBits = prefix % 8;
	int fullBytesToCompare = partialByte - 1;
	while(fullBytesToCompare >= 0)
	{
	    if(myAddress[fullBytesToCompare] != otherAddress[fullBytesToCompare])
		return false;
	    fullBytesToCompare--;
	}
	
	byte myByte = myAddress[partialByte];
	byte otherByte = otherAddress[partialByte];
	
	myByte &= -1 - (1 << (remainingBits + 1)) - 1; 
	otherByte &= -1 - (1 << (remainingBits + 1)) - 1;
	
	return myByte == otherByte;
    }
    
    public int hashCode()
    {
	return base.hashCode() + prefix;
    }
   
    public boolean equals(Object other)
    {
	if(other instanceof Prefix)
	{
	    return base.equals(((Prefix) other).base) && prefix == ((Prefix) other).prefix;
	}
	return false;
    }
    
    public String toString()
    {
	return base.toString().substring(1) + "/" + prefix;
    }
}
