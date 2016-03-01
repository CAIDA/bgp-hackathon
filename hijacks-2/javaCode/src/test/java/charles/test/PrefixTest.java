package charles.test;
import static org.junit.Assert.*;

import java.net.UnknownHostException;

import org.junit.Test;

public class PrefixTest
{
    @Test
    public void isSubsetTest() throws UnknownHostException
    {
	Prefix parent = new Prefix("127.36.192.0/18");
	Prefix child = new Prefix("127.36.193.0/24");
	Prefix not1 = new Prefix("127.36.191.0/24");
	Prefix not2 = new Prefix("127.36.192.0/17");
	Prefix not3 = new Prefix("127.45.192.0/20");
	
	assertTrue(parent.isSubset(child));
	assertTrue(parent.isSubset(parent));
	
	assertFalse(parent.isSubset(not1));
	assertFalse(parent.isSubset(not2));
	assertFalse(parent.isSubset(not3));
    }
}
