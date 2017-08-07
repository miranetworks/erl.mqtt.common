%%
%% Copyright (C) 2015-2017 by krasnop@bellsouth.net (Alexei Krasnopolski)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%		 http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License. 
%%


-ifdef(TEST).

-define(test_fragment_set_test_flag, 
handle_call({set_test_flag, Flag}, _From, State) ->	
	{reply, ok, State#connection_state{test_flag = Flag}};
).

-define(test_fragment_break_connection, 
handle_call({publish, _}, _, #connection_state{test_flag = break_connection, transport = Transport} = State) ->
	Transport:close(State#connection_state.socket),
	{stop, normal, State};
).

-define(test_fragment_skip_send_publish, 
handle_call({publish, #publish{qos = QoS} = Params}, {_, Ref}, State) when ((QoS =:= 1) orelse (QoS =:= 2)) and (State#connection_state.test_flag =:= skip_send_publish) ->
	Packet_Id = State#connection_state.packet_id,
	Storage = State#connection_state.storage,
%% store message before sending
	Prim_key = #primary_key{client_id = (State#connection_state.config)#connect.client_id, packet_id = Packet_Id},
	Storage:save(State#connection_state.end_type, #storage_publish{key = Prim_key, document = Params#publish{dir = out, last_sent = publish}}),
	{reply, {ok, Ref}, State};
).

-define(test_fragment_skip_rcv_publish, 
		{publish, _QoS, _Packet_Id, _Topic, _Payload, Tail} when State#connection_state.test_flag =:= skip_rcv_publish ->
			process(State, Tail);
).

-define(test_fragment_skip_send_puback, 
				1 when State#connection_state.test_flag =:= skip_send_puback ->
					delivery_to_application(State, Record),
					process(State, Tail);
).

-define(test_fragment_skip_send_pubrec, 
				2 when State#connection_state.test_flag =:= skip_send_pubrec ->
					process(State, Tail);
).

-define(test_fragment_skip_rcv_puback, 
		{puback, _Packet_Id, Tail} when State#connection_state.test_flag =:= skip_rcv_puback ->
			process(State, Tail);
).

-define(test_fragment_skip_rcv_pubrec, 
		{pubrec, _Packet_Id, Tail} when State#connection_state.test_flag =:= skip_rcv_pubrec ->
			process(State, Tail);
).

-define(test_fragment_skip_send_pubrel, 
		{pubrec, Packet_Id, Tail} when State#connection_state.test_flag =:= skip_send_pubrel ->
			case maps:get(Packet_Id, Processes, undefined) of
				{From, Params} ->
%% store message before pubrel
					Prim_key = #primary_key{client_id = (State#connection_state.config)#connect.client_id, packet_id = Packet_Id},
					Storage:save(State#connection_state.end_type, #storage_publish{key = Prim_key, document = #publish{last_sent = pubrel}}),
					New_processes = Processes#{Packet_Id => {From, Params#publish{last_sent = pubrel}}},
					process(State#connection_state{processes = New_processes}, Tail);
				undefined ->
					process(State, Tail)
			end;
).

-define(test_fragment_skip_rcv_pubrel, 
		{pubrel, _Packet_Id, Tail} when State#connection_state.test_flag =:= skip_rcv_pubrel ->
			process(State, Tail);
).

-define(test_fragment_skip_send_pubcomp, 
		{pubrel, Packet_Id, Tail} when State#connection_state.test_flag =:= skip_send_pubcomp ->
			case maps:get(Packet_Id, Processes, undefined) of
				{_From, _Params} ->
%% discard PI before pubcomp send
					Prim_key = #primary_key{client_id = (State#connection_state.config)#connect.client_id, packet_id = Packet_Id},
					Storage:remove(State#connection_state.end_type, Prim_key),
					New_processes = maps:remove(Packet_Id, Processes),
					process(State#connection_state{processes = New_processes}, Tail);
				undefined ->
					process(State, Tail)
			end;
).

-define(test_fragment_skip_rcv_pubcomp, 
		{pubcomp, _Packet_Id, Tail} when State#connection_state.test_flag =:= skip_rcv_pubcomp ->
			process(State, Tail);
).

-else.
-define(test_fragment_set_test_flag, ).
-define(test_fragment_break_connection, ).
-define(test_fragment_skip_send_publish, ).
-define(test_fragment_skip_rcv_publish, ).
-define(test_fragment_skip_send_puback, ).
-define(test_fragment_skip_send_pubrec, ).
-define(test_fragment_skip_rcv_puback, ).
-define(test_fragment_skip_rcv_pubrec, ).
-define(test_fragment_skip_send_pubrel, ).
-define(test_fragment_skip_rcv_pubrel, ).
-define(test_fragment_skip_send_pubcomp, ).
-define(test_fragment_skip_rcv_pubcomp, ).
-endif.
