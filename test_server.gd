extends Node

func _ready():
	print("Sunucuya bağlanılıyor...")
	var url = "https://vei6fhd2sj.execute-api.us-east-2.amazonaws.com/default/OyunSunucuKodu"
	
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_request_completed)
	
	var data = {
		"user_id": "test_kullanici_123",
		"faction": "MMO"
	}
	var json_string = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]
	
	var error = http.request(url, headers, HTTPClient.METHOD_POST, json_string)
	if error != OK:
		print("İstek gönderilemedi! Hata kodu: ", error)

func _on_request_completed(result, response_code, headers, body):
	print("Sunucudan Yanıt Geldi!")
	print("Durum Kodu: ", response_code)
	var json = JSON.new()
	var parse_error = json.parse(body.get_string_from_utf8())
	if parse_error == OK:
		print("Gelen Mesaj: ", json.data)
	else:
		print("Gelen Ham Veri: ", body.get_string_from_utf8())