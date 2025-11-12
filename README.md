# contec08a
Logged data recovery for Contec08a veterinary sphygmomanometer (blood-pressure meter).

This program locates a USB-connected Contec08a instrument, and recovers the logged data which is documented as comprising up to 100 records for each of three users. Output format is comma-separated variables (CSV), with a header line and the user number appended as a comment to each record.

Because device detection uses low-level facilities it is not expected that this will be directly useful on anything other than Linux.

For convenience a project information file for the Lazarus IDE is provided, but at least as yet there is no useful GUI interface. As such I suggest that the Makefile is used for compilation.
