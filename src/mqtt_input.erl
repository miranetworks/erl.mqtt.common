%%
%% Copyright (C) 2015-2017 by krasnop@bellsouth.net (Alexei Krasnopolski)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License. 
%%

%% @since 2015-12-25
%% @copyright 2015-2017 Alexei Krasnopolski
%% @author Alexei Krasnopolski <krasnop@bellsouth.net> [http://krasnopolski.org/]
%% @version {@version}
%% @doc @todo Add description to mqtt_client_input.


-module(mqtt_input).

%%
%% Include files
%%
-include("mqtt.hrl").

%% ====================================================================
%% API functions
%% ====================================================================
-export([
	input_parser/1
]).

-ifdef(TEST).
-export([
	decode_remaining_length/1
]).
-endif.

%% ====================================================================
%% Internal functions
%% ====================================================================

input_parser(<<?CONNECT_PACK_TYPE, Bin/binary>>) ->
	{RestBin, Length} = decode_remaining_length(Bin),
	case RestBin of
		<<4:16, "MQTT", 4:8, RestBin0/binary>> ->
			parse_connect_packet('3.1.1', Length - 10, RestBin0);
		<<6:16, "MQIsdp", 3:8, RestBin0/binary>> ->
			parse_connect_packet('3.1', Length - 12, RestBin0);
		_ ->
			{connect, undefined, Bin}
	end;

input_parser(<<?CONNACK_PACK_TYPE, 2:8, 0:7, SP:1, Connect_Return_Code:8, Tail/binary>>) ->
	{connack, SP, Connect_Return_Code, return_code_response(Connect_Return_Code), Tail};
input_parser(<<?PUBLISH_PACK_TYPE, DUP:1, QoS:2, RETAIN:1, Bin/binary>>) ->
	{RestBin, Length} = decode_remaining_length(Bin),
	<<L:16, TopicBin:L/binary, RestBin1/binary>> = RestBin,
	Topic = unicode:characters_to_list(TopicBin, utf8),
	case QoS of
		0 ->
			PL = Length - L - 2,
			<<Payload:PL/binary, Tail/binary>> = RestBin1,
			{publish, #publish{topic = Topic, dup = DUP, qos = QoS, retain = RETAIN, payload = Payload, dir = in}, 0, Tail};
		_ when (QoS =:= 1) orelse (QoS =:= 2) ->
			PL = Length - L - 4,
			<<Packet_Id:16, Payload:PL/binary, Tail/binary>> = RestBin1,
			{publish, #publish{topic = Topic, dup = DUP, qos = QoS, retain = RETAIN, payload = Payload, dir = in}, Packet_Id, Tail};
		_ -> true
	end;
input_parser(<<?PUBACK_PACK_TYPE, 2:8, Packet_Id:16, Tail/binary>>) -> {puback, Packet_Id, Tail};
input_parser(<<?PUBREC_PACK_TYPE, 2:8, Packet_Id:16, Tail/binary>>) -> {pubrec, Packet_Id, Tail};
input_parser(<<16#60:8, 2:8, Packet_Id:16, Tail/binary>>) -> {pubrel, Packet_Id, Tail}; %% @todo issue with websocket client from HiveMQ
input_parser(<<?PUBREL_PACK_TYPE, 2:8, Packet_Id:16, Tail/binary>>) -> {pubrel, Packet_Id, Tail};
input_parser(<<?PUBCOMP_PACK_TYPE, 2:8, Packet_Id:16, Tail/binary>>) -> {pubcomp, Packet_Id, Tail};
input_parser(<<?SUBSCRIBE_PACK_TYPE, Bin/binary>>) ->
	{RestBin, Length} = decode_remaining_length(Bin),
	L = Length - 2,
	<<Packet_Id:16, RestBin1:L/binary, Tail/binary>> = RestBin,
	{subscribe, Packet_Id, parse_subscription(RestBin1, []), Tail};
input_parser(<<?SUBACK_PACK_TYPE, Bin/binary>>) ->
	{RestBin, Length} = decode_remaining_length(Bin),
	L = Length - 2,
	<<Packet_Id:16, Return_codes:L/binary, Tail/binary>> = RestBin,
	{suback, Packet_Id, binary_to_list(Return_codes), Tail};
input_parser(<<?UNSUBSCRIBE_PACK_TYPE, Bin/binary>>) ->
	{RestBin, Length} = decode_remaining_length(Bin),
	L = Length - 2,
	<<Packet_Id:16, RestBin1:L/binary, Tail/binary>> = RestBin,
	{unsubscribe, Packet_Id, parse_unsubscription(RestBin1, []), Tail};
input_parser(<<?UNSUBACK_PACK_TYPE, Bin/binary>>) ->
	{RestBin, _Length} = decode_remaining_length(Bin),
	<<Packet_Id:16, Tail/binary>> = RestBin,
	{unsuback, Packet_Id, Tail};
input_parser(<<?PING_PACK_TYPE, 0:8, Tail/binary>>) -> {pingreq, Tail};
input_parser(<<?PINGRESP_PACK_TYPE, 0:8, Tail/binary>>) -> {pingresp, Tail};
input_parser(<<?DISCONNECT_PACK_TYPE, 0:8, Tail/binary>>) -> {disconnect, Tail};
input_parser(Binary) ->
	lager:error("Unknown Binary received ~p~n", [Binary]),
	{unparsed, Binary}.

return_code_response(0) -> "0x00 Connection Accepted";
return_code_response(1) -> "0x01 Connection Refused, unacceptable protocol version";
return_code_response(2) -> "0x02 Connection Refused, identifier rejected";
return_code_response(3) -> "0x03 Connection Refused, Server unavailable";
return_code_response(4) -> "0x04 Connection Refused, bad user name or password";
return_code_response(5) -> "0x05 Connection Refused, not authorized";
return_code_response(_) -> "Return Code is not recognizable".

decode_remaining_length(Binary) ->
	decode_rl(Binary, 1, 0).

decode_rl(_, MP, L) when MP > (128 * 128 * 128) -> {error, L};
decode_rl(<<0:1, EncodedByte:7, Binary/binary>>, MP, L) ->
	NewL = L + EncodedByte * MP,
	{Binary, NewL};
decode_rl(<<1:1, EncodedByte:7, Binary/binary>>, MP, L) ->
	NewL = L + EncodedByte * MP,
	decode_rl(Binary, MP * 128, NewL).

parse_connect_packet(MQTT_Version, Length, Binary) ->
	<<	User:1, Password:1, Will_retain:1, Will_QoS:2, Will:1, Clean_Session:1, _:1, 
		Keep_Alive:16, RestBin1:Length/binary, Tail/binary>> = Binary,
	<<Client_id_bin_size:16, Client_id:Client_id_bin_size/binary, RestBin2/binary>> = RestBin1,

	case Will of
		0 ->
			WillTopic = <<>>,
			WillMessage = <<>>,
			RestBin3 = RestBin2;
		1 -> 
			<<SizeT:16, WillTopic:SizeT/binary, SizeM:16, WillMessage:SizeM/binary, RestBin3/binary>> = RestBin2
	end,

	case User of
		0 ->
			UserName = <<>>,
			RestBin4 = RestBin3;
		1 -> 
			<<SizeU:16, UserName:SizeU/binary, RestBin4/binary>> = RestBin3
	end,

	case Password of
		0 ->
			Password_bin = <<>>;
		1 -> 
			<<SizeP:16, Password_bin:SizeP/binary>> = RestBin4
	end,
	
	Config = #connect{
		client_id = binary_to_list(Client_id), %% @todo utf8 unicode:characters_to_list(Topic, utf8),???
		user_name = binary_to_list(UserName),
		password = Password_bin,
		will = Will,
		will_qos = Will_QoS,
		will_retain = Will_retain,
		will_topic = binary_to_list(WillTopic),
		will_message = WillMessage,
		clean_session = Clean_Session,
		keep_alive = Keep_Alive,
		version = MQTT_Version
	},
	{connect, Config, Tail}.

parse_subscription(<<>>, Subscriptions) -> lists:reverse(Subscriptions);
parse_subscription(<<Size:16, Topic:Size/binary, QoS:8, BinartRest/binary>>, Subscriptions) ->
	parse_subscription(BinartRest, [{Topic, QoS} | Subscriptions]).

parse_unsubscription(<<>>, Topics) -> lists:reverse(Topics);
parse_unsubscription(<<Size:16, Topic:Size/binary, BinartRest/binary>>, Topics) ->
	parse_unsubscription(BinartRest, [Topic | Topics]).
