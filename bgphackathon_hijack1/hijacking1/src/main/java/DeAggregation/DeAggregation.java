package DeAggregation;

import DetectionModules.Config;
import org.apache.commons.net.util.SubnetUtils;
import org.apache.commons.net.util.SubnetUtils.SubnetInfo;

import java.io.IOException;
import java.util.StringJoiner;

public class DeAggregation{
    private String node;
    private String prefix;

    public DeAggregation(String node, String prefix){
        this.node = node;
        this.prefix = prefix;
    }

    public void doDeAggr2(){

        if(Config.ongoing){
            return;
        }

        String pfxLength = prefix.split("/")[1];    // find the prefix len using / delimeter
        String pfxStr = prefix.split("/")[0];    // find the prefix len using / delimeter

        String[] strlist = pfxStr.split("\\.");
        StringJoiner sj1 = new StringJoiner(".");
        for(String str: strlist){
            sj1.add(str);
        }
        String firstPrefix = sj1.toString() + "/24";

        int oldnum = Integer.valueOf(strlist[2]);
        strlist[2]  = String.valueOf(oldnum+1);
        StringJoiner sj2 = new StringJoiner(".");
        for(String str: strlist){
            sj2.add(str);
        }
        String secondPrefix = sj2.toString() + "/24";



        /*
        System.out.println("Input prefix:"  +   this.prefix);
        System.out.println("First prefix: " +   firstPrefix);
        System.out.println("Second prefix: "+   secondPrefix);
        */

        // TODO: maybe run it with sudo privilages!!

        String command = "./peering prefix announce -m " + node + " " + firstPrefix;
        System.out.println(command);
        command = "./peering prefix announce -m " + node + " " + secondPrefix;
        System.out.println(command);

        try {

            Process firstAnnouncement = Runtime.getRuntime().exec("./peering prefix announce -m " + node + " " + firstPrefix);
            firstAnnouncement.waitFor();

            Process secAnnouncement = Runtime.getRuntime().exec("./peering prefix announce -m " + node + " " + secondPrefix);
            secAnnouncement.waitFor();
        } catch (IOException | InterruptedException e) {
            e.printStackTrace();
        }

        Config.ongoing = true;
    }

    public void doDeAggr(){
        String pfxLength = prefix.split("/")[1];    // find the prefix len using / delimeter
        int newPrefix = Integer.parseInt(pfxLength) + 1;

        SubnetUtils subUtil = new SubnetUtils(this.prefix);
        SubnetInfo  subInfo = subUtil.getInfo();

        String[] parts = subInfo.getLowAddress().split("\\.");

        // construct the first subprefix
        String firstPrefix = parts[0] + "." + parts[1] + "." +
                parts[2] + "." + fixLowPrefix(parts[3]) + "/" + newPrefix;

        SubnetUtils subUtil2 = new SubnetUtils(firstPrefix);
        SubnetInfo  subInfo2 = subUtil2.getInfo();


        parts = subInfo2.getHighAddress().split("\\.");

        // construct the second subprefix
        String secondPrefix = parts[0] + "." + parts[1] + "." +
                            parts[2] + "." + fixHighPrefix(parts[3]) + "/" + newPrefix;

        System.out.println("Input prefix:"  +   this.prefix);
        System.out.println("First prefix: " +   firstPrefix);
        System.out.println("Second prefix: "+   secondPrefix);

        // TODO: maybe run it with sudo privilages!!

        /*
        try {
            Process firstAnnouncement = Runtime.getRuntime().exec("./peering prefix announce -m " + node + " " + firstPrefix);
            firstAnnouncement.waitFor();

            Process secAnnouncement = Runtime.getRuntime().exec("./peering prefix announce -m " + node + " " + secondPrefix);
            secAnnouncement.waitFor();
        } catch (IOException e) {
            e.printStackTrace();
        } catch (InterruptedException e) {
            e.printStackTrace();
        }

        */
    }

    private static String fixLowPrefix(String part){
        int newPart = Integer.parseInt(part);
        newPart--;
        return Integer.toString(newPart);
    }

    private static String fixHighPrefix(String part){
        int newPart = Integer.parseInt(part);
        newPart+=2;
        return Integer.toString(newPart);
    }

}