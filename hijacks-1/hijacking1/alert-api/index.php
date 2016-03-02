<?php
	define("MY_PREFIX", "184.164.230.0/23");
	define("CLASSPATH", "C:/Users/Andrew/IdeaProjects/test/out/production/test");
	define("MAIN", "com.company.Test");

	function build_command($data_source, $timestamp, $prefix_old, $as_old, $prefix_new, $as_new, $as_path_new_str, $country_code, $raw_data_str){
		$command = "";
		$command = "java -classpath " . CLASSPATH . " " . MAIN . " " . $data_source . " " . $timestamp . " " . $prefix_old . " " . $as_old  . " " . $prefix_new . " " . $as_new . " " .
		           $as_path_new_str . " " . $country_code . " " . $raw_data_str;
		return $command;
	}

	// from http://stackoverflow.com/questions/6041741/fastest-way-to-check-if-a-string-is-json-in-php
	function isJson($string) {
 		json_decode($string);
 		return (json_last_error() == JSON_ERROR_NONE);
	}

	if(isset($_POST['is_data_request']) && $_POST['is_data_request'] == True){
		// echo json full of info
	}

	if (isset($_POST['is_alert']) && $_POST['is_alert'] == True) {
		
		$response = array();
		$response['acknowledge_data_source'] = false;
		$response['acknowledge_timestamp'] = false;
		$response['acknowledge_prefix_old'] = false;
		$response['acknowledge_AS_old'] = false;
		$response['acknowledge_prefix_new'] = false;
		$response['acknowledge_AS_new'] = false;
		$response['acknowledge_AS_path_new'] = false;
		$response['acknowledge_country_code'] = false;
		$response['acknowledge_raw_data'] = false;

		// get data_source
		if ( isset($_POST['data_source']) && is_string($_POST['data_source']) ) {
			$data_source = $_POST['data_source'];
			$response['acknowledge_data_source'] = true;
		}

		// get timestamp
		if ( isset($_POST['timestamp']) && is_numeric($_POST['timestamp']) ) {
			$timestamp = $_POST['timestamp'];
			$response['acknowledge_timestamp'] = true;
		}

		// get prefix_old
		if ( isset($_POST['prefix_old']) && is_string($_POST['prefix_old']) ) {
			$prefix_old = $_POST['prefix_old'];
			$response['acknowledge_prefix_old'] = true;
		}

		// get as_old
		if ( isset($_POST['AS_old']) && is_numeric($_POST['AS_old']) ) {
			$as_old = $_POST['AS_old'];
			$response['acknowledge_AS_old'] = true;
		}

		// get prefix_new
		if ( isset($_POST['prefix_new']) && is_string($_POST['prefix_new']) ) {
			$prefix_new = $_POST['prefix_new'];
			$response['acknowledge_prefix_new'] = true;
		}

		// get as_new
		if ( isset($_POST['AS_new']) && is_numeric($_POST['AS_new']) ) {
			$as_new = $_POST['AS_new'];
			$response['acknowledge_AS_new'] = true;
		}

		// get as_path_new
		if ( isset($_POST['AS_path_new']) && is_string($_POST['AS_path_new']) && isJson($_POST['AS_path_new']) ) {
			$as_path_new_str = $_POST['AS_path_new'];
			$as_path_new = json_decode($as_path_new_str);
			$as_path_new_str = str_replace(' ', '', $as_path_new_str);
			if(is_array($as_path_new)){
				$response['acknowledge_AS_path_new'] = true;
			} else{
				$as_path_new = array();
			}
		}

		// get country_code
		if ( isset($_POST['country_code']) && is_string($_POST['country_code']) ) {
			$country_code = $_POST['country_code'];
			$response['acknowledge_country_code'] = true;
		}

		// get raw_data
		if ( isset($_POST['raw_data']) && is_string($_POST['raw_data']) && isJson($_POST['raw_data']) ) {
			$raw_data_str = $_POST['raw_data'];
			$raw_data_str = str_replace(' ', '', $raw_data_str);
			$raw_data = json_decode($raw_data_str);
			if(is_object($raw_data)){
				$response['acknowledge_raw_data'] = true;
			} else{
				$raw_data = array();
			}
		}

		// acknolwedge receipt of alert
		echo json_encode($response);

		// call exec of some Java
		$command = build_command($data_source, $timestamp, $prefix_old, $as_old, $prefix_new, $as_new, $as_path_new_str, $country_code, $raw_data_str);
		echo $command;
		exec($command, $output);
	}
?>