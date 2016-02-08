package DetectionModules;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;
import org.json.simple.JSONArray;
import org.json.simple.JSONObject;

import java.io.*;
import java.net.InetSocketAddress;
import java.nio.charset.Charset;

/**
 * Created by Gabriel on 2/6/2016.
 */
public class Cassandra {

    public Cassandra() {
        HttpServer server = null;
        try {
            server = HttpServer.create(new InetSocketAddress(8000), 0);
            server.createContext("/cass", new CassHandler());
            server.setExecutor(null); // creates a default executor
            server.start();
        } catch (IOException e) {
            e.printStackTrace();
        }

    }

    static class CassHandler implements HttpHandler {
        public void handle(HttpExchange t) throws IOException {
            BufferedReader bis = new BufferedReader(new
                    InputStreamReader(t.getRequestBody(),"utf-8"));

            String inputLine;
            while ((inputLine = bis.readLine()) != null){
                System.out.println(inputLine);
                writeToViz(inputLine);
            }
            bis.close();
            // From now on, the right way of moving from bytes to utf-8 characters:

            String response = "This is the response";
            t.sendResponseHeaders(200, response.length());
            OutputStream os = t.getResponseBody();
            os.write(response.getBytes());
            os.close();
        }
    }

    static private void writeToViz(String input){

        String[] parts = input.split("&");

        JSONObject inner = new JSONObject();
        inner.put("id", 0);
        inner.put("AS_prefix_new", parts[4].split("=")[1]);
        inner.put("AS_new", parts[0].split("=")[1]);
        inner.put("country_code_AS_new", parts[1].split("=")[1]);
        inner.put("AS_old", parts[2].split("=")[1]);
        inner.put("country_code_AS_old", parts[3].split("=")[1]);
        inner.put("AS_prefix_old", parts[4].split("=")[1]);

        JSONArray points = new JSONArray();
        points.add(inner.toJSONString());

        JSONObject outer = new JSONObject();
        outer.put("points",points.toJSONString());

        try {

            FileWriter file = new FileWriter("C:\\Users\\Gabriel\\IdeaProjects\\bgphackathon_hijack1\\hijacking1\\viz\\map_points.json");
            file.write(outer.toJSONString());
            file.flush();
            file.close();

        } catch (IOException e) {
            e.printStackTrace();
        }
    }

}
