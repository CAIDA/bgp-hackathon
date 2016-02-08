package DetectionModules;

import DeAggregation.DeAggregation;

import java.io.*;
import java.net.Socket;
import java.util.Objects;

/**
 * Created by gabriel on 2/7/16.
 */
public class BGPStream {
    private int port = 8888;
    private int BUFFER_SIZE = 65536;


    public BGPStream(){

    }

    public void start(){
        Socket clientSocket = null;
        try {
            clientSocket = new Socket("comet-17-06.sdsc.edu", 8888);
            BufferedReader bis = new BufferedReader(new
                    InputStreamReader(clientSocket.getInputStream()));

            String inputLine;
            while ((inputLine = bis.readLine()) != null){
                System.out.println(inputLine);

                if(isAnomaly(inputLine)){
                    // test anomaly
                    // need to react.

                    DeAggregation deaggr = new DeAggregation("gatech01", Config.ownPrefix);
                    deaggr.doDeAggr2();
                }
            }
            clientSocket.close();
        } catch (IOException e) {
            System.err.println("No connection! Retrying in 1 sec");
            try {
                Thread.sleep(1000);
            } catch (InterruptedException e1) {
                e1.printStackTrace();
            }
            this.start();
        }

    }


    public boolean isAnomaly(String input){

        boolean isAnomaly = false;

        String[] strlist;

        strlist = input.split(" ");
        String prefix = strlist[0];
        String originAsn = strlist[strlist.length-1];

        if(Objects.equals(prefix,Config.ownPrefix)){
            if(!Objects.equals(originAsn,Config.ownAsn)){
                isAnomaly = true;
            }
        }

        return isAnomaly;
    }

    public static void main(String[] args) {
        BGPStream stream = new BGPStream();

        boolean anomaly1 = stream.isAnomaly("184.164.228.0/24 1 2 3 4 5");
        boolean anomaly2 = stream.isAnomaly("184.164.228.0/24 1 2 3 4 47065");

        System.out.println(String.format("%s %s",anomaly1,anomaly2));
    }
}
