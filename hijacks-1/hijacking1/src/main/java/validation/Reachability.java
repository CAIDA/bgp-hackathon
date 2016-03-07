package validation;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.net.InetAddress;
import java.util.ArrayList;
import java.util.List;

/**
 * Created by Mingwei Zhang on 2/6/2016.
 *
 * Detect reachability information
 */
public class Reachability{

    /**
     * Ping one single IP and test if this IP address is reachable;
     *
     * @param ipAddress the IP address in question
     * @return true if reachable; false if unreachable
     */
    public boolean pingIp(String ipAddress){

        boolean pingResult = false;
        final InetAddress host;
        try {
            host = InetAddress.getByName(ipAddress);
            pingResult = host.isReachable(1500);
        } catch (IOException e) {
            e.printStackTrace();
        }

        return pingResult;
    }

    /**
     * Ping a list of IP addresses, and return the reachability results as a list of boolean values
     * @param ipAddrList the list of IP addresses
     * @return a list of boolean values; true means reachable and false means unreachable.
     */
    public List<Boolean> pingIpList(List<String> ipAddrList){

        List<Boolean> resultList = new ArrayList<Boolean>();
        for(String ip: ipAddrList){
            resultList.add(pingIp(ip));
        }
        return resultList;
    }


    public static void main(final String[] args) throws IOException {

        Reachability reachability = new Reachability();
        BufferedReader br = null;
        try {
            String sCurrentLine;
            br = new BufferedReader(new FileReader("alexa-top-100.txt"));
            while ((sCurrentLine = br.readLine()) != null) {
                boolean result = reachability.pingIp(sCurrentLine);
                System.out.println(String.format("%s\t%s",sCurrentLine,result));
            }
        } catch (IOException e) {
            e.printStackTrace();
        } finally {
            try {
                if (br != null)br.close();
            } catch (IOException ex) {
                ex.printStackTrace();
            }
        }
    }
}
