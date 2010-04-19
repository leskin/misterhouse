#Category=Chuck
# 132 columns max
#23456789112345678921234567893123456789412345678951234567896123456789712345678981234567899123456789012345678911234567892123456789312

#@ This code sets up voice commands, reports stats every minute, and does housekeeping.

# This file goes in your mh/mycode directory

# Originally by Kent Noonan, Joel Davidson & Dan Arnold
# Close to full rewrite/overhaul by Marc MERLIN 2009/07/22


use vars qw(@omnilist @omnistat @omniname @omnioffset $stat_cool_temp $stat_heat_temp $stat_mode $stat_fan $stat_hold 
  $stat_indoor_temp $cmd  $stat_model @v_omnistat_fan @v_omnistat_resume @v_omnistat_hold @v_omnistat_mode 
  @v_omnistat_cool_sp @v_omnistat_heat_sp @v_omnistat_setting @stat_reset_timer $house_stat $mbr_stat $test_stat);

# noloop=start
# define the stats and which serial address they are using.
# put the omnistat IDs in there, for me I only have 2: ID 1 and ID 2
# Note that the code was written so that the IDs don't have to be contiguous
@omnilist = (1, 2);

# It's important to only run the object creation once so that their cache isn't destroyed

# but we'll skip the simple way because we'll make MH happy by creating the Omnistat objects
# by binding them to a real variable, which only then we can assign to an array element.
# This would work fine if/when everyone uses the @omnistat array, but misterhouse likes
# having named variables like the ones below, so we skip this:
#foreach my $omnistat (@omnilist)			
#{
#    $omnistat[$omnistat] = new Omnistat($omnistat);
#}

# We end up with this instead: a separate mh variable for each stat so that it can be found
# by code looking for omnistats among all mh objects (which won't see arrays like @omnistat)
# but we can't even do this because of the mh parser:
#$omnistat[1] = ($house_stat = new Omnistat(1));
#$omnistat[2] = ($mbr_stat = new Omnistat(2));
# so we need this for now (until everyone uses the @omnistat array) -- merlin
$house_stat = new Omnistat(1);
$omnistat[1] = $house_stat;
$mbr_stat = new Omnistat(2);
$omnistat[2] = $mbr_stat;


# Map names. Make sure to match the index numbers from above
$omniname[1] = "Main";
$omniname[2] = "MBR";

# what offset in seconds is each omnistat scanned at?
# (you can't do them all at once, it can hang the main loop a bit)
$omnioffset[1] = 0;
$omnioffset[2] = 30;

foreach my $omnistat (@omnilist)
{
    my $temprange = join(",", (50..90));
    $stat_reset_timer[$omnistat] = new Timer();
    # little trick to support an index if you have more than one stat, and no index otherwise
    my $statidx = " ";
    $statidx = " $omniname[$omnistat]" if ($#omnilist > 0);

    $v_omnistat_fan[$omnistat]=new Voice_Cmd("Set$statidx Thermostat fan [on,auto]");
    $v_omnistat_resume[$omnistat]=new Voice_Cmd("Resume $statidx Thermostat");
    $v_omnistat_hold[$omnistat]=new Voice_Cmd("Set$statidx Thermostat hold [on,off]");
    $v_omnistat_mode[$omnistat]=new Voice_Cmd("Set$statidx Thermostat mode [off,heat,cool,auto]");
    $v_omnistat_cool_sp[$omnistat]=new Voice_Cmd("Set$statidx Thermostat cool setpoint to [$temprange]");
    $v_omnistat_heat_sp[$omnistat]=new Voice_Cmd("Set$statidx Thermostat heat setpoint to [$temprange]");
    $v_omnistat_setting[$omnistat]=new Voice_Cmd("What is the$statidx thermostat set to");

    # With these, you can either send 
    # 'Set Thermostat cool setpoint to 68' 
    # if you have one thermostat, or 
    # 'Set Bedroom Thermostat cool setpoint to 72'
    # if you have multiple
}
# noloop=stop

# The rest should be part of the main loop
foreach my $omnistat (@omnilist)
{
    if ($Reload or $Reread or $New_Day) {
	# Talking to Omnistats can be a bit expensive for mh, due to the main loop hangs this can create, so we'll wait 
	# 60 seconds after the event to space things out from whatever else might be happening at those magic times
	# (plus an offset for each omnistat id)
	$stat_reset_timer[$omnistat]->set(60 + $omnistat*4);
    }

    if ($stat_reset_timer[$omnistat]->expired) {
	Omnistat::omnistat_log("$omniname[$omnistat] Omnistat: Resetting time");
	#$omnistat[$omnistat]->cooling_anticipator('10');
	#$omnistat[$omnistat]->heating_anticipator('10');
	#$omnistat[$omnistat]->cooling_cycle_time('8');
	#$omnistat[$omnistat]->heating_cycle_time('8');
	$omnistat[$omnistat]->set_time;
    }
    
    # update data once a minute, per omnistat offset seconds.
    if ($New_Second and $Second eq $omnioffset[$omnistat]) { 
	# we make the extended group1 call that also retreives the stat's output status
	my ($cool_sp, $heat_sp, $mode, $fan, $hold, $temp, $output) = $omnistat[$omnistat]->read_group1("true");

	my $stat_type = $omnistat[$omnistat]->get_stat_type;
	# This mashes $hold and $mode together from registers cached in the group1 call and outputs a combined string
	$mode = $omnistat[$omnistat]->get_mode;

	Omnistat::omnistat_log("".$omniname[$omnistat]." Omnistat $stat_type: Indoor temp is $temp, HVAC Command: $output, heat to $heat_sp, cool to $cool_sp, mode: $mode");

	# only store the temperature from the first stat (which we'll assume is master)
	$Weather{TempIndoor} = $temp  if ($omnistat == $omnilist[0]);
    }

    if ($state = $v_omnistat_fan[$omnistat]->said) {
	$omnistat[$omnistat]->fan($state);
    }
    
    if ($state = $v_omnistat_resume[$omnistat]->said) {
	$omnistat[$omnistat]->restore_setpoints;
    }
    
    if ($state = $v_omnistat_hold[$omnistat]->said) {
	$omnistat[$omnistat]->hold($state);
    }
    
    if ($state = $v_omnistat_mode[$omnistat]->said) {
	$omnistat[$omnistat]->mode($state);
    }
    
    if ($state = $v_omnistat_cool_sp[$omnistat]->said) {
	$omnistat[$omnistat]->cool_setpoint($state);
	speak "Air conditioning set to $state degrees for $omniname[$omnistat] Omnistat";
	Omnistat::omnistat_log("$omniname[$omnistat] Omnistat: Air conditioning set to $state degrees", 2);
    }
    
    if ($state = $v_omnistat_heat_sp[$omnistat]->said) {
	$omnistat[$omnistat]->heat_setpoint($state);
	speak "Heat set to $state degrees for $omniname[$omnistat] Omnistat";
	Omnistat::omnistat_log("$omniname[$omnistat] Omnistat: Heat set to $state degrees", 2);
    }
    
    if ($state = $v_omnistat_setting[$omnistat]->said) {
	my ($heat,$cool);
	$cool = $omnistat[$omnistat]->get_cool_sp;
	$heat = $omnistat[$omnistat]->get_heat_sp;
	speak "cool setpoint $cool, heat setpoint $heat";
	Omnistat::omnistat_log("$omniname[$omnistat] Omnistat: cool setpoint $cool, heat setpoint $heat", 2);
    }
    
    # Old code left over in case it's useful to some -- merlin
    # note that you have to turn hold mode off to change setpoints
    #if (defined ($state = state_changed $mode) && $state eq 'away') {
    #  Omnistat::omnistat_log("$omniname[$omnistat] Omnistat: Setting to away mode");
    #  $omnistat[$omnistat]->hold('off');
    #  $omnistat[$omnistat]->cool_setpoint('95');
    #  $omnistat[$omnistat]->heat_setpoint('50');
    #  $omnistat[$omnistat]->hold('on');
    #}
      
    #if (defined ($state = state_changed $mode) && $state eq 'home') {
    #  Omnistat::omnistat_log("$omniname[$omnistat] Omnistat: Setting to home mode");
    #  $omnistat[$omnistat]->hold('off');
    #  $omnistat[$omnistat]->cool_setpoint('78');
    #  $omnistat[$omnistat]->heat_setpoint('68');
    #  $omnistat[$omnistat]->hold('on');
    #}
    
    if (time_now '7:15 PM')  {
	if ($omnistat[$omnistat]->get_filter_reminder == 0)
	{
	    speak "Replace the furnace filter linked to $omniname[$omnistat] Omnistat";
	    Omnistat::omnistat_log("$omniname[$omnistat] Omnistat: replace the filter", 0);
	}
    }
    
    
    if (new_minute 5)
    {
	# Set the outside temp on the thermostat if available (refreshing this value should cause the
	# stat to display the outside temperature on the display).
	if ($Weather{TempOutdoor}) {
	    Omnistat::omnistat_log("$omniname[$omnistat] Omnistat: Setting outside temperature to $Weather{TempOutdoor}", 2);
	    $omnistat[$omnistat]->outdoor_temp($Weather{TempOutdoor});   
	}
    }
    
    if ($state = $omnistat[$omnistat]->state_now) {
	# this may or many not be useful to you, you can comment it out if you're not planning on using state changes for coding
	Omnistat::omnistat_log("".$omniname[$omnistat]." Omnistat State set to: $state", 3);
    }
}