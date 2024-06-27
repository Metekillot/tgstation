/// Called when a techweb design is researched (datum/design/researched_design, custom)
#define COMSIG_TECHWEB_ADD_DESIGN "techweb_add_design"

/// Called when a techweb design is removed (datum/design/removed_design, custom)
#define COMSIG_TECHWEB_REMOVE_DESIGN "techweb_remove_design"

/* Signals for research interfaces, which are currently just the research consoles and PDA programs. */


/* Called when a research interface successfully communicates with a techweb for the first time; whether it's a new console, new user, or both
* datum/source - the techweb
* obj/item/card/inserting_id - when the interface was accessed by an ID card
* mob/user - when the interface was accessed by something with inherent access
*/
#define COMSIG_TECHWEB_NEW_CONNECTION "research_console_new_connection"


/// Called when a research interface is queried by the server controller; validates that this is returning queries
#define COMSIG_RESEARCH_CONSOLE_INFO_QUERIED "console_info_queried"
#define RESEARCH_CONSOLE_QUERY_VALID (1<<0)
#define RESEARCH_CONSOLE_QUERY_INVALID (1<<1)


/// Called when a research interface has its access (un)locked by the server controller
#define COMSIG_RESEARCH_CONSOLE_TOGGLE_LOCK "research_console_toggle_lock"
