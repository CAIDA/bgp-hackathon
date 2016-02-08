package DetectionModules;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import org.json.simple.JSONObject;
import org.json.simple.parser.JSONParser;

public class FeedReader {
    public static void main(String[] args) {

        Process p;
        JSONParser parser = new JSONParser();
        //String my_prefix = args[1];

        try{
            p = Runtime.getRuntime().exec("python /home/dev/code/hijacks-2/hijacks_feed.py");
            // p.waitFor();

            BufferedReader reader =
                    new BufferedReader(new InputStreamReader(p.getInputStream()));

            String line = "";
            while ((line = reader.readLine())!= null) {
                //System.out.println(line);
                Object obj = parser.parse(line.substring(1));
                JSONObject conflict_alert = (JSONObject)obj;
                JSONObject conflict_dict = (JSONObject)conflict_alert.get("conflict_with");
                //JSONObject conflict_dict_obj =
                //    (JSONObject)parser.parse(conflict_dict);
                String conflicted_prefix =
                        conflict_dict.get("prefix").toString();
                System.out.println(conflicted_prefix);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}

