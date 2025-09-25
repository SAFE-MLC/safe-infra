\c safe;

INSERT INTO events(id,name,start_at,end_at,status)
VALUES ('evt_1','Concierto', NOW()+INTERVAL '1 hour', NOW()+INTERVAL '5 hours','SCHEDULED');

INSERT INTO gates(id,event_id,name) VALUES ('gate_1','evt_1','Puerta Norte');
INSERT INTO zones(id,event_id,name) VALUES ('zone_vip','evt_1','VIP');
INSERT INTO zone_checkpoints(id,zone_id,name) VALUES ('zc_10','zone_vip','Entrada VIP A');

INSERT INTO staff(id,display_name,role,pin_hash,gate_id)
VALUES ('carlos','Carlos','GATE','1234','gate_1');
INSERT INTO staff(id,display_name,role,pin_hash,zone_checkpoint_id)
VALUES ('maya','Maya','ZONE','4321','zc_10');

INSERT INTO tickets(id,event_id,holder,status)
VALUES ('t1','evt_1','Alice','ACTIVE'), ('t2','evt_1','Bob','ACTIVE');

INSERT INTO zone_entitlements(ticket_id,zone_id) VALUES ('t1','zone_vip');
