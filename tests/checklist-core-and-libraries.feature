# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_admin — Core & Libraries

  @kora_admin @checklist @checklist:kora_admin:open-admin-menu @cat:core-and-libraries @needs:admin
  Scenario: Open admin menu (/admin, F7)
    """
    Checklist test: As staff run /admin or press F7: Players, Reports, My Tools, Server, Development workspaces filtered by your tier.
    """
    When I run the command "/admin"
    Then the "kora_admin:menu" app opens
    And I confirm: the admin menu shows Players, Reports, My Tools, Server and Development workspaces
    And I confirm: only the workspaces allowed for my staff tier are shown
    When I manually: close the menu
    And I press the "F7" key
    Then the "kora_admin:menu" app should be open
    And I confirm: the admin menu shows the same workspaces as before

  @kora_admin @checklist @checklist:kora_admin:permission-tiers @cat:core-and-libraries @needs:admin @manual
  Scenario: Permission tiers (support to owner)
    """
    Checklist test: Test with each ACE role: menu items and commands hidden or denied per tier; ACE and Discord roles both grant.
    """
    When I manually: test with an account for each ACE role from support to owner
    Then I confirm: menu items and commands above my tier are hidden or denied
    And I confirm: roles granted by ACE and by Discord both give access

  @kora_admin @checklist @checklist:kora_admin:player-profile @cat:core-and-libraries @needs:admin
  Scenario: Player profile and Copy Player Info
    """
    Checklist test: Select an online player in Players: profile shows job, balances, health, ping; Copy Player Info copies visible fields.
    """
    When I run the command "/admin"
    And I manually: select an online player in the Players workspace
    Then I confirm: the profile shows job, balances, health and ping
    When I manually: click Copy Player Info
    Then I should see a notification containing "Player information copied"
    And I confirm: the copied text contains the visible profile fields

  @kora_admin @checklist @checklist:kora_admin:heal-revive-kill @cat:core-and-libraries @needs:admin
  Scenario: Heal, revive, kill, selfrevive
    """
    Checklist test: Run /heal, /revive, /kill [id|me] and /selfrevive; heal also restores hunger/thirst; dead player is fully revived.
    """
    When I run the command "/kill"
    Then I should be dead
    When I run the command "/revive"
    Then I should be alive
    When I run the command "/kill"
    And I run the command "/selfrevive"
    Then I should be alive
    When I run the command "/heal"
    Then my metadata "hunger" should be "100"
    And my metadata "thirst" should be "100"
    When I manually: run /heal, /revive and /kill with another player's id
    Then I confirm: each command affects the target player, and a dead target is fully revived

  @kora_admin @checklist @checklist:kora_admin:health-armor @cat:core-and-libraries @needs:admin
  Scenario: Set /health and /armor
    """
    Checklist test: Run /health 50 and /armor 100; percent maps to ped max; setting health on a dead ped revives.
    """
    When I manually: run /health 50
    Then I confirm: my health is about 50 percent of the ped maximum
    When I manually: run /armor 100
    Then my armour should be 100
    When I run the command "/kill"
    And I manually: run /health 50 while dead
    Then I should be alive
    And I confirm: my health is about 50 percent

  @kora_admin @checklist @checklist:kora_admin:god-devmode-invisible @cat:core-and-libraries @needs:admin
  Scenario: God, devmode and invisible toggles
    """
    Checklist test: Run /god, /devmode, /invisible on self (mod) and on others (admin).
    """
    When I run the command "/god"
    Then I confirm: god mode toggles on for me
    When I run the command "/devmode"
    Then I confirm: dev mode toggles on for me
    When I run the command "/invisible"
    Then I confirm: I become invisible
    When I manually: run /god, /devmode and /invisible with another player's id as admin
    Then I confirm: each toggle applies to the other player

  @kora_admin @checklist @checklist:kora_admin:freeze-spectate @cat:core-and-libraries @needs:admin
  Scenario: Freeze and spectate
    """
    Checklist test: Run /freeze <id> and /spectate <id>; menu closes for spectate and returns you after.
    """
    When I manually: run /freeze with another player's id
    Then I confirm: the other player is frozen and cannot move
    When I manually: run /spectate with another player's id
    Then I confirm: the admin menu closes and I spectate the target
    When I press the "BACK" key
    Then I should see a notification containing "Stopped spectating"
    And I confirm: I am returned to my original position

  @kora_admin @checklist @checklist:kora_admin:warn-kick @cat:core-and-libraries @needs:admin @manual
  Scenario: Warn, warnings and kick
    """
    Checklist test: Run /warn <id> reason, /warnings <id>, /kick <id> reason; confirmation dialog appears in the menu.
    """
    When I manually: run /warn with another player's id and a reason
    Then I confirm: a confirmation dialog appears in the menu
    When I manually: run /warnings with that player's id
    Then I confirm: the warning I issued is listed
    When I manually: run /kick with that player's id and a reason
    Then I confirm: a confirmation dialog appears and the player is kicked after confirming

  @kora_admin @checklist @checklist:kora_admin:ban-unban @cat:core-and-libraries @needs:admin @manual
  Scenario: Ban and unban (incl. offline)
    """
    Checklist test: Run /ban and /unban; offline players resolvable; banned player is refused on connect; Offline Bans tab lists.
    """
    When I manually: run /ban with an online player's id, a duration and a reason
    Then I confirm: the player is banned and kicked
    When I manually: run /ban with an offline player's identifier
    Then I confirm: the offline player is resolved and banned
    When I manually: ask a second player to connect while banned
    Then I confirm: the banned player is refused on connect
    When I manually: open the Offline Bans tab
    Then I confirm: the Offline Bans tab lists the bans
    When I manually: run /unban for the banned player
    Then I confirm: the ban is removed and the player can connect

  @kora_admin @checklist @checklist:kora_admin:teleport-commands @cat:core-and-libraries @needs:admin
  Scenario: Teleport: /tpm /tpcoords /goto /bring
    """
    Checklist test: Test /tpm to waypoint, /tpcoords x y z (or vec3/vector4 paste), /goto, /bring, /sendback, /tpback with ground snapping.
    """
    When I manually: set a map waypoint and run /tpm
    Then I confirm: I teleport to the waypoint and land on the ground
    When I manually: run /tpcoords with x y z, then with a pasted vec3 or vector4
    Then I confirm: I teleport to the given coordinates both times
    When I manually: run /goto with another player's id
    Then I confirm: I teleport to that player
    When I manually: run /bring with another player's id
    Then I confirm: the other player is teleported to me
    When I manually: run /sendback with that player's id
    Then I confirm: the other player returns to their previous position
    When I run the command "/tpback"
    Then I confirm: I return to my previous position

  @kora_admin @checklist @checklist:kora_admin:noclip @cat:core-and-libraries @needs:admin
  Scenario: Noclip (/noclip)
    """
    Checklist test: Toggle /noclip as admin: fly through world; toggling off restores normal movement.
    """
    When I run the command "/noclip"
    Then I confirm: I can fly through the world
    When I run the command "/noclip"
    Then I confirm: normal movement is restored and I no longer pass through the world

  @kora_admin @checklist @checklist:kora_admin:vehicle-spawn @cat:core-and-libraries @needs:admin
  Scenario: Vehicle spawn and delete (/car /veh /dv /fix)
    """
    Checklist test: Run /car <model>, /veh, /dv, /fix; My Tools > Vehicles has Spawn from Code and the catalogue.
    """
    When I run the command "/car"
    Then I should be in a vehicle
    When I run the command "/fix"
    Then I confirm: the vehicle is repaired
    When I run the command "/dv"
    Then the vehicle should be deleted
    When I run the command "/veh"
    Then I confirm: a vehicle spawns in front of me
    When I manually: open My Tools > Vehicles
    Then I confirm: Spawn from Code and the catalogue are available

  @kora_admin @checklist @checklist:kora_admin:give-vehicle-keys @cat:core-and-libraries @needs:admin
  Scenario: Give vehicle and keys
    """
    Checklist test: Run /givevehicle <id> <model> <plate>; target gets an owned vehicle in their garage.
    /givekeys is no longer an admin command (kora_vehiclekeys owns it); admin key grants by plate are
    kora_vehiclekeys' /addkeys <id> <plate>.
    """
    Given I am in the driver seat of a "test_car"
    When I manually: run /givevehicle with another player's id, a model and a plate
    Then I confirm: the other player owns the new vehicle in their garage

  @kora_admin @checklist @checklist:kora_admin:money-commands @cat:core-and-libraries @needs:admin @manual
  Scenario: Money: /givemoney /removemoney /setmoney
    """
    Checklist test: Run each with id, account (cash/bank), amount, reason; balance changes and is audited.
    """
    When I manually: ask a second player for their id and note it
    And I manually: run /givemoney with that id, account cash, an amount and a reason
    Then I confirm: the other player's cash balance changed by the given amount
    When I manually: run /removemoney with that id, account bank, an amount and a reason
    Then I confirm: the other player's bank balance decreased by the given amount
    When I manually: run /setmoney with that id, account cash, an amount and a reason
    Then I confirm: the other player's cash balance equals the amount set
    And I confirm: each money action appears in the audit log

  @kora_admin @checklist @checklist:kora_admin:item-commands @cat:core-and-libraries @needs:admin
  Scenario: Items: /giveitem /removeitem /clearinventory
    """
    Checklist test: Give and remove items with optional info; /clearinventory asks for confirmation.
    """
    When I manually: run /giveitem with my own id, an item name, a count and optional info
    Then I confirm: the item is added to my inventory with the info given
    When I manually: run /removeitem with my own id, the same item and a count
    Then I confirm: the item count in my inventory decreases by that count
    When I run the command "/clearinventory"
    Then I confirm: a confirmation prompt appears before my inventory is cleared
    When I manually: confirm the prompt
    Then I confirm: my inventory is empty

  @kora_admin @checklist @checklist:kora_admin:job-gang-commands @cat:core-and-libraries @needs:admin @manual
  Scenario: Job and gang: /setjob /setgang /setduty
    """
    Checklist test: Set job/gang with grade and toggle duty on a target player; results show in profile.
    """
    When I manually: ask a second player for their id
    And I manually: run /setjob with that id, a job and a grade
    And I manually: run /setgang with that id, a gang and a grade
    And I manually: run /setduty with that id to toggle their duty
    Then I confirm: the other player's job, gang and duty status changed accordingly
    And I confirm: the results show in that player's profile in the admin menu

  @kora_admin @checklist @checklist:kora_admin:world-commands @cat:core-and-libraries @needs:admin
  Scenario: Announce, weather and time
    """
    Checklist test: /announce plays alert sound for all; /weather and /time change environment; /serverinfo prints stats.
    """
    When I manually: run /announce with a short message
    Then I confirm: every player hears the alert sound and sees the announcement
    When I manually: run /weather with a valid weather type
    Then I confirm: the weather changes to that type
    When I manually: run /time with an hour
    Then I confirm: the in-game clock changes to that time
    When I run the command "/serverinfo"
    Then I confirm: server stats are printed

  @kora_admin @checklist @checklist:kora_admin:reports-player @cat:core-and-libraries
  Scenario: Player reports (/report, /reportstatus, /reportreply)
    """
    Checklist test: As a normal player submit /report <type> <msg>, check /reportstatus <id> and reply; cooldown limits spam.
    """
    When I manually: as a normal non-staff player run /report with a type and a message
    Then I confirm: I see a confirmation with a report id
    When I manually: run /reportstatus with that report id
    Then I confirm: the report status is shown
    When I manually: run /reportreply with that report id and a message
    Then I confirm: my reply is added to the report
    When I manually: run /report several times quickly
    Then I should see a notification containing "Wait a few seconds before another command"

  @kora_admin @checklist @checklist:kora_admin:reports-staff @cat:core-and-libraries @needs:admin
  Scenario: Staff reports queue (/reports, /reportclaim)
    """
    Checklist test: As staff open /reports or the Reports workspace: filter, claim, reply, resolve, dismiss and reopen; live updates.
    """
    When I run the command "/reports"
    Then I confirm: the reports queue opens
    When I manually: filter the reports list
    Then I confirm: the list shows only matching reports
    When I manually: claim a report
    Then I confirm: the report shows as claimed by me
    When I manually: reply to the report
    Then I confirm: the reply is sent to the reporter
    When I manually: resolve the report, then dismiss another, then reopen one
    Then I confirm: each report status updates correctly
    And I confirm: the queue updates live when a new report arrives

  @kora_admin @checklist @checklist:kora_admin:audit-log @cat:core-and-libraries @needs:admin
  Scenario: Audit log (/adminlog)
    """
    Checklist test: Run /adminlog or Server > Audit Log (admin) and confirm earlier staff actions appear.
    """
    When I run the command "/adminlog"
    Then I confirm: the audit log opens and lists my earlier staff actions
    When I manually: open Server > Audit Log in the admin menu
    Then I confirm: the same earlier staff actions appear

  @kora_admin @checklist @checklist:kora_admin:temp-access @cat:core-and-libraries @needs:admin @manual
  Scenario: Temporary access grants
    """
    Checklist test: Run /granttempaccess <id> <role> <minutes> and /revoketempaccess; grant expires and is audited.
    """
    When I manually: ask a second player for their id
    And I manually: run /granttempaccess with that id, a role and a number of minutes
    Then I confirm: the other player gains the role access
    When I manually: run /revoketempaccess with that id
    Then I confirm: the other player's temporary access is removed
    When I manually: run /granttempaccess with that id, a role and 1 minute, then wait for it to expire
    Then I confirm: the access expires after the time
    And I confirm: grant and revoke appear in the audit log

  @kora_admin @checklist @checklist:kora_admin:permanent-permissions @cat:core-and-libraries @needs:admin @manual
  Scenario: Set/revoke permission and restart resource
    """
    Checklist test: Owner: /setpermission, /revokepermission, /restartresource <name>; admin denied.
    """
    When I manually: as owner run /setpermission with a target id and a role
    Then I confirm: the permission is granted
    When I manually: run /revokepermission with the same target id
    Then I confirm: the permission is revoked
    When I manually: run /restartresource with a resource name
    Then I confirm: the resource restarts
    When I manually: as an admin (not owner) run /setpermission, /revokepermission and /restartresource
    Then I confirm: each command is denied for the admin

  @kora_admin @checklist @checklist:kora_admin:appearance-menus @cat:core-and-libraries @needs:admin @manual
  Scenario: Clothing, barber and tattoo menus
    """
    Checklist test: Select a player and use /clothingmenu, /barbermenu, /tattoomenu to open appearance sessions for them.
    """
    When I manually: ask a second player for their id
    And I manually: run /clothingmenu with that id
    Then I confirm: a clothing session opens for that player
    When I manually: run /barbermenu with that id
    Then I confirm: a barber session opens for that player
    When I manually: run /tattoomenu with that id
    Then I confirm: a tattoo session opens for that player

  @kora_admin @checklist @checklist:kora_admin:dev-builders @cat:core-and-libraries @needs:admin
  Scenario: Developer tools (/entitypicker /devplacement /devzone)
    """
    Checklist test: Admin Development tab: Inspect Entity (H copies model, X closes), prop placement and zone creator.
    """
    When I run the command "/admin"
    Then the "kora_admin:menu" app should be open
    When I manually: open the Development tab and choose Inspect Entity
    And I manually: aim at an entity and press H
    Then I confirm: the model name is shown and copied
    When I manually: press X
    Then I confirm: the entity picker closes
    When I run the command "/devplacement"
    Then I confirm: the prop placement tool starts
    When I run the command "/devzone"
    Then I confirm: the zone creator starts

  @kora_admin @checklist @checklist:kora_admin:entity-spawn @cat:core-and-libraries @needs:admin
  Scenario: Spawn ped/prop entities (/entity /deleteentity)
    """
    Checklist test: Spawn a ped or prop model locally for self/target; delete my entities removes them.
    """
    When I manually: run /entity with a ped model for myself
    Then I should see a notification containing "Spawned entity"
    And I confirm: the ped spawns in front of me
    When I manually: run /entity with a prop model for a target player
    Then I confirm: the prop spawns locally in front of the target
    When I run the command "/deleteentity"
    Then I should see a notification containing "Deleted your last admin-spawned entity"
    And I confirm: my spawned entities are removed

  @kora_admin @checklist @checklist:kora_admin:config-editor-owner @cat:core-and-libraries @needs:admin
  Scenario: Owner configuration editor tab
    """
    Checklist test: Owner: Server > Configuration tab edits kora config values live.
    """
    When I run the command "/admin"
    And I manually: as owner open Server > Configuration tab
    Then the "kora_admin:config" app should be open
    And I confirm: the configuration catalog loads
    When I manually: edit a config value and save
    Then I should see a notification containing "Configuration updated live."
    And I confirm: the changed value takes effect in game
