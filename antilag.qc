#include "defs.qc"


class Antilag {
    #pragma warning disable Q207

    
    static nonvirtual void(string fullcmd) SV_ParseClientCommand =
    {
        local float argc = tokenize(fullcmd);
        local string cmd = argv(0);

        if (cmd == "playerexflags")
        {
            self.antilag_playerexflags = stof(argv(1));
            sprint(self, "PlayerEXFlags set to ");
            sprint(self, ftos(self.antilag_playerexflags));
            sprint(self, "\n");
            return;
        }

        clientcommand(self, fullcmd);
    };

    
    // QCAntilag: clear player positions
    static nonvirtual void() ClearLastOrigin =
    {
        local float i;
        for(i = 0; i < ANTILAG_STATES; i++)
        {
            self.antilag_lastorigin[i] = 0;
            self.antilag_lastorigintime[i] = 0;
        }
    };

    // QCAntilag: compare angles to see if they're within margin of error
    static nonvirtual float(vector ang1, vector ang2) CompareNetAngles =
    {
        // putting this in a loop inexplicably causes a crash... no idea
        // the math here is just replicating WriteAngle behavior
        ang1[0] = floor(ang1[0]*(256/360) - 0.5) & 255;
        ang2[0] = floor(ang2[0]*(256/360) - 0.5) & 255;
        ang1[1] = floor(ang1[1]*(256/360) - 0.5) & 255;
        ang2[1] = floor(ang2[1]*(256/360) - 0.5) & 255;
        ang1[2] = floor(ang1[2]*(256/360) - 0.5) & 255;
        ang2[2] = floor(ang2[2]*(256/360) - 0.5) & 255;

        return (ang1 == ang2);
    };
    

    // QCAntilag: check angles for spawn
    static nonvirtual void() CheckSpawnTest =
    {
        if (self.antilag_flags & ANTILAG_FL_SPAWNTEST && self.antilag_spawn_time)
        {
            if (CompareNetAngles(self.v_angle, self.antilag_spawn_angles))
            {
                self.antilag_responsetime1 = (time - self.antilag_spawn_time) * 1000;
                self.antilag_spawn_time = 0;
            }
            else if (time - self.antilag_spawn_time > 0.5) // timeout, something went wrong. not exactly unexpected with this hack
            {
                self.antilag_spawn_time = 0;
            }
        }
    };


    // QCAntilag: Think function for client ping impulse
    static nonvirtual void () client_ping_think =
    {
        local entity client;

        client = find(world, ::classname, "player");
        while (client)
        {
            // If for some reason the flag was missed
            if(client.antilag_flags & ANTILAG_FL_RESPONSECHECK)
                client.antilag_flags -= ANTILAG_FL_RESPONSECHECK;

            client.antilag_responsetime3 = client.antilag_responsetime2;
            client.antilag_responsetime2 = client.antilag_responsetime1;

            if (client.finaldest_y > self.finaldest_x) // if we got a packet back
            {
                self.antilag_flags &= ~ANTILAG_FL_SPAWNTEST;
                client.antilag_responsetime1 = (floor(client.finaldest_y - self.finaldest_x) - 16);

                // cap to acceptable values
                client.antilag_responsetime1 = client.antilag_responsetime1 < 0 ? 0 : client.antilag_responsetime1;
                client.antilag_responsetime1 = client.antilag_responsetime1 > ANTILAG_MAX_RESPONSETIME ? ANTILAG_MAX_RESPONSETIME : client.antilag_responsetime1;
            }
            else // packet dropped, lets make something up
            {
                if (self.finaldest_z > client.finaldest_y) // client hasn't responded in a long time, probably cl_filterstuffcmd 1
                {
                    client.antilag_flags |= ANTILAG_FL_SPAWNTEST;
                    client.antilag_responsetime1 = client.antilag_responsetime;
                }
                else
                    client.antilag_responsetime1 = client.antilag_responsetime;
            }

            if (client.antilag_responsetime2 > 0)
            {
                if (client.antilag_responsetime3 > 0)
                {
                    client.antilag_responsetime = ((client.antilag_responsetime1 + client.antilag_responsetime2 + client.antilag_responsetime3) / 3);
                }
                else
                {
                    client.antilag_responsetime = ((client.antilag_responsetime1 + client.antilag_responsetime2) / 2);
                }

            }
            else
            {
                client.antilag_responsetime = client.antilag_responsetime1;
            }
            client = find(client, ::classname, "player");
        }

        remove(self);
    };

    // QCAntilag: Request ping (response) time for all clients
    static nonvirtual void () client_responsetime_get_all =
    {
        if (is_running_fte) // if we're on FTE, we can use the QW way
        {
            for(entity pl = find(world, ::classname, "player"); pl; pl = find(pl, ::classname, "player"))
            {
                pl.antilag_responsetime = infokeyf(pl, "ping") - 8; // account for QW input frame timey-ness

                // cap to acceptable values
                pl.antilag_responsetime = pl.antilag_responsetime < 0 ? 0 : pl.antilag_responsetime;
                pl.antilag_responsetime = pl.antilag_responsetime > ANTILAG_MAX_RESPONSETIME ? ANTILAG_MAX_RESPONSETIME : pl.antilag_responsetime;
            }

            responsetimecheck = (time + 3); // we're using engine stuff, so we can speed this polling up a bit
            return;
        }

        local entity ping;

        for(entity pl = find(world,::classname,"player");pl; pl = find(pl,::classname,"player"))
        {
            if(pl.deadflag == DEAD_NO) {
                pl.antilag_flags |= ANTILAG_FL_RESPONSECHECK;
                stuffcmd(pl,"kill\n");
            }
        }

        ping = spawn();
        ping.classname = "client_ping";
        ping.owner = world;
        ping.nextthink = time + 2;
        ping.think = client_ping_think;
        ping.finaldest_x = (time * 1000);
        ping.finaldest_z = ((time - 20) * 1000);

        responsetimecheck = (time + 10);
    };

    // QCAntilag: Store the ping (response) time for a ping entity
    static nonvirtual void () client_responsetime_set =
    {
        self.finaldest_y = (time * 1000);
    };


    // QCAntilag: Debug function to see response times and frames
    static nonvirtual void () client_responsetime_show =
    {
        /*
        //don't let players spam this
        if (time < self.antilag_spamtime)
            return;

        self.antilag_spamtime = (time + 5);
        */
        
        sprint(self, "response time3: ");
        sprint(self, ftos(self.antilag_responsetime3));
        sprint(self, "\n");
        sprint(self, "response time2: ");
        sprint(self, ftos(self.antilag_responsetime2));
        sprint(self, "\n");
        sprint(self, "response time1: ");
        sprint(self, ftos(self.antilag_responsetime1));
        sprint(self, "\n");
        sprint(self, "response time:  ");
        sprint(self, ftos(self.antilag_responsetime));
        sprint(self, "\n");
        sprint(self, "current origin: ");
        sprint(self, vtos(self.origin));
        sprint(self, "\n");

        float i;
        for(i = 0; i < ANTILAG_STATES; i++)
        {
            sprint(self, "last frame");
            sprint(self, ftos(i));
            sprint(self, ": ");
            sprint(self, vtos(self.antilag_lastorigin[i]));
            sprint(self, " ");
            sprint(self, ftos(self.antilag_lastorigintime[i]));
            sprint(self, "\n");
        }
    };


    // QCAntilag: Rotate player positions
    static nonvirtual void () UpdateLastOrigin =
    {
        // push array towards the end, this could be replaced with a circular buffer
        float i;
        for(i = ANTILAG_STATES-1; i > 0; i--)
        {
            self.antilag_lastorigin[i] = self.antilag_lastorigin[i-1];
            self.antilag_lastorigintime[i] = self.antilag_lastorigintime[i-1];
        }

        self.antilag_lastorigin[0] = self.origin;
        self.antilag_lastorigintime[0] = (time * 1000);
    };

    
    

    // QCAntilag: Rewind an entity "e" to "rewindtime" to check for lag-compensated hits
    static nonvirtual void (entity e, float rewindtime) antilag_rewind =
    {
        vector rewindorigin;

        float i;
        for(i = 0; i < ANTILAG_STATES; i++)
        {
            // if we encounter a cleared value
            if (antilag_lastorigintime[i] == 0)
            {
                // if this is the first array entry, the entire thing is cleared
                if (i == 0) {
                    // return without messing with origin
                    return;
                }
                // use the previous one
                else if (i > 0) {
                    rewindorigin = e.antilag_lastorigin[i - 1];
                    break;
                }
            }
            // if we've gone over our target rewind time, use this origin
            else if (rewindtime > e.antilag_lastorigintime[i])
            {
                rewindorigin = e.antilag_lastorigin[i];
                break;
            }
        }

        if(rewindorigin != [0,0,0]) // JPiolho: Sometimes it's 0 0 0 and it flickers the screen. Not sure why.
            setorigin(e, rewindorigin);
    };

    

    // QCAntilag: Rewind all players to "pingtime" except for player "ignore"
    static nonvirtual void (float pingtime, entity ignore) antilag_rewind_players =
    {
        local entity player;

        float timestamp_we_want = ((time * 1000) - pingtime);

        player = find(world, ::classname, "player");

        while (player)
        {
            if (player.deadflag == DEAD_NO)
            {
                // Store the player's .origin off to a temporary .antilag_hold_origin
                player.antilag_hold_origin = player.origin;
                // Don't rewind self
                if (player != ignore)
                {
                    // Rewind the player entity back to timestamp_we_want
                    antilag_rewind(player, timestamp_we_want);
                }
            }
            player = find(player, ::classname, "player");
        }
    };


    // QCAntilag: Restore all players' .origin back to where the server thinks they are
    static nonvirtual void () antilag_restore_players =
    {
        local entity player;

        player = find(world, ::classname, "player");

        while (player)
        {
            if (player.deadflag == DEAD_NO)
            {
                // Put everybody back where the server thinks they belong
                setorigin(player, player.antilag_hold_origin);
            }
            player = find(player, ::classname, "player");
        }
    };

    // QCAntilag: Extrapolate the visual antilagged position of projectiles to send to clients
    static nonvirtual void(entity missile) Extrapolate_AntilagProjectile =
    {
        // Original physics position should have been stored in missile.antilag_hold_origin already

        // Make sure to multiply by 0.001 to convert into seconds for desired velocity
        traceline(missile.origin, missile.origin + (missile.velocity * missile.antilag_responsetime * 0.001), FALSE, missile);
        // Move to the extrapolated position for good visuals
        setorigin(missile, trace_endpos);
    };

    // QCAntilag: .think function for antilag projectiles (i.e. rockets, nails/spikes)
    static nonvirtual void() ThinkMovetype_AntilagProjectile =
    {
        self.think = ThinkMovetype_AntilagProjectile;
        self.nextthink = time + 0.01;

        setorigin(self, self.antilag_hold_origin);

        // If our SSQC is running at hyper fast framerate for some reason (FTE)
        local float delta = frametime;
        if (is_running_fte)
        {
            if (cvar("sv_gameplayfix_multiplethinks") || delta < 0.01)
                delta = 0.01;
        }

        // Use the client's response time to temporarily move all other player entities back in time
        antilag_rewind_players(self.antilag_responsetime, self.owner);

        // Trace a line from current position to the place where we'll be after the next frame
        traceline(self.origin, self.origin + (self.velocity * delta), FALSE, self);

        // Actually move the missile
        setorigin(self, trace_endpos);

        // If we run into something
        if (trace_fraction < 1)
        {
            // Call T_MissileTouch()
            if (self.touch)
            {
                other = trace_ent;
                self.touch();
            }

            // Call the other entity's .touch function (if it has one)
            if (trace_ent && trace_ent.touch)
            {
                entity oself = self;
                other = self;
                ::self = trace_ent;
                self.touch();
                ::self = oself;
            }
        }

        // Put all the player entities back to their actual (server) positions
        antilag_restore_players();

        // Track our true position
        self.antilag_hold_origin = self.origin;

        // Run extrapolation
        Extrapolate_AntilagProjectile(self);
    };


    static nonvirtual void() PlayerSpawn = {
        // QCAntilag: Track spawn angles and time so we can determine ping time from fixangle if needed
		if (self.antilag_flags & ANTILAG_FL_SPAWNTEST) // send the angles manually if we're using spawntest ping check
		{
			self.fixangle = FALSE;
			self.antilag_spawn_angles = self.angles;
			self.antilag_spawn_time = time;

			msg_entity = self;

			WriteByte(MSG_ONE, SVC_SETANGLE);
			WriteAngle(MSG_ONE, self.angles[0]);
			WriteAngle(MSG_ONE, self.angles[1]);
			WriteAngle(MSG_ONE, self.angles[2]);
		}

		// QCAntilag: clear antilag rewind positions so we don't rewind players back to their dead positions after respawn
		ClearLastOrigin();
    };

    static nonvirtual void() ClientConnect = {
        // QCAntilag: tell ourselves which server we're in
        if (is_running_fte) // if we're on FTE, we can use the QW way
        {
            sprint (self, "QCAntilag in FTE server mode\n");
            string protocol = infokey(self, "protocol");
            float is_qw_client = (strstrofs(protocol, "quakeworld") != -1);

            if (!self.antilag_playerexflags) 
            {
                if (infokey(self, "playerexflags") == "")
                {
                    if (is_qw_client) // if we're QW and haven't gotten any exflags yet, assume never change
                        self.antilag_playerexflags |= PEF_CHANGENEVER;
                }
                else // if we have userinfo playerexflags, use those
                {
                    self.antilag_playerexflags = infokeyf(self, "playerexflags");
                }
            }

        } else {
            sprint (self, "QCAntilag in QE server mode\n");
        }
    };

    static nonvirtual void() PlayerPreThink = {
        CheckSpawnTest();
    };

    static nonvirtual void() PlayerPostThink = {
        if(self.impulse == 37) {
            client_responsetime_show();
            self.impulse = 0;
        }

        if(time > self.antilag_updatetime)
        {
            UpdateLastOrigin();
            self.antilag_updatetime = time + 0.01;
        }
    };

    static nonvirtual void() StartFrame =
    {
        // QCAntilag: Periodically get clients' ping (response) times
        if (time > responsetimecheck)
        {
            client_responsetime_get_all();
        }
    };

    static nonvirtual float() ClientKill =
    {
        if(self.antilag_flags & ANTILAG_FL_RESPONSECHECK)
        {
            self.antilag_flags -= ANTILAG_FL_RESPONSECHECK;
            client_responsetime_set();
            return TRUE;
        }

        return FALSE;
    };

    static nonvirtual void(entity sender, entity projectile) SetAsAntilagProjectile =
    {
        if(!(sender.flags & FL_CLIENT))
            return;

        // use custom a movement .think
        projectile.movetype = MOVETYPE_NONE;
        projectile.think = ThinkMovetype_AntilagProjectile;
        projectile.nextthink = time + 0.01;

        // set .antilag_responsetime to owner's so position can be compensated for antilag
        projectile.antilag_responsetime = sender.antilag_responsetime;

        // store the physics version of the missile's location
        projectile.antilag_hold_origin = projectile.origin;

        // run extrapolation, so for QW clients we avoid visual strange-ness
        Extrapolate_AntilagProjectile(projectile);
    };

    #pragma warning enable Q207
};