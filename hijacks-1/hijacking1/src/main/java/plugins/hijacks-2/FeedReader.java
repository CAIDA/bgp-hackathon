
import java.io.BufferedReader;
import java.io.InputStreamReader;
import org.json.simple.JSONObject;
import org.json.simple.JSONArray;
import org.json.simple.parser.JSONParser;

public class FeedReader {
    public static void main(String[] args) {

        Process p;
        String python_path = "/home/dev/code/hijacks-2/hijacks_feed.py";
        JSONParser parser = new JSONParser();
        String my_prefix = args[0];
        try{
            if(args[1].equals("fake")){
                python_path = "/home/dev/code/bgphackathon_hijack1/hijacking1/scripts/fake_feed.py";
            }
        } catch(Exception e){
            // do nothing
        }
        System.out.println(python_path);
        System.out.println(args.length);

        try{
            p = Runtime.getRuntime().exec("python " + python_path);
           // p.waitFor();

            BufferedReader reader = 
                 new BufferedReader(new InputStreamReader(p.getInputStream()));

            String line = "";			
            while ((line = reader.readLine())!= null) {
	        //System.out.println(line);
                Object obj = parser.parse(line.substring(2, line.length()-1));
                JSONObject conflict_alert = (JSONObject)obj;
                JSONObject conflict_dict = 
                    (JSONObject)conflict_alert.get("conflict_with");
                //JSONObject conflict_dict_obj = 
                //    (JSONObject)parser.parse(conflict_dict);
                String conflicted_prefix = 
                    conflict_dict.get("prefix").toString();
                if( conflicted_prefix.equals(my_prefix) ){
                    System.out.println(conflicted_prefix);
                }
        }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}

