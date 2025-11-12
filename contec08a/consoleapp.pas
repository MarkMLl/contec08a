(* Lazarus+FPC 2.2.6+3.2.2 on Linux Lazarus+FPC 2.2.6+3.2.2 on Linux Lazarus+FP *)

unit ConsoleApp;

(* This is the greater part of a console program which reads historical data    *)
(* from a Contec08A veterinary sphygmomanometer (HID device 0483:5750 which is  *)
(* actually pinched from STMicroelectronics vendor pool) and sends it to        *)
(* stdout.                                                      MarkMLl.        *)

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

const
  Vid= $0483;
  Pid= $5750;

type
  TOperation= (opLive, opPlayback, opQuery, opQueryVendor, opQueryModel,
                                                        opQueryDevice, opQueryInfo);
  TWriteLn= procedure(const s: string);

(* Verbosity (one or more -v options) controls the amount of text sent to the   *)
(* output device (stdout in unix terms). If decremented to zero (-q option)     *)
(* there will be no output, other than what is being sent to a background       *)
(* database etc.                                                                *)
(*                                                                              *)
(* Prolixity (one or more -d options) controls the amount of debugging text     *)
(* sent to the stderr device. If omitted all HID reconnection etc. will happen  *)
(* silently, this is probably what's expected during normal operation.          *)

var
  Verbosity: integer= 1;
  Prolixity: integer= 0;
  GetUser: integer= 1;

(* GNU-mandated support for --version and --help.
*)
procedure DoVersion(const projName: string);

(* GNU-mandated support for --version and --help.
*)
procedure DoHelp();

(* Return true if there is no parameter. This includes the case where the
  commandline ends with --, which under GNU conventions may be used to
  terminate a sequence of options.
*)
function NoParams(): boolean;

(* Return the name of the HID device prefixed with /dev/ if it has been seen
  (typically at program startup) and not removed.
*)
function FindContec08aPort(): ansistring;

(* This is the inner loop of the main function. If the final parameter is nil
  then output each decoded line using WriteLn(), otherwise call the indicated
  writer procedure which will typically send the output to the GUI.
*)
function RunConsoleApp2(var portFile: File; op: TOperation;
                        var pleaseStop: boolean; writer: TWriteLn= nil): integer;

(* Main function, return 0 if no error.
*)
function RunConsoleApp(portName: string): integer;


implementation

uses
  BaseUnix, MonitorHidLinux, IniFilesAbout;

type
  TContec08aBuffer= array[0..63] of byte;


(* GNU-mandated support for --version and --help.
*)
procedure DoVersion(const projName: string);

begin
  WriteLn();
  WriteLn(projName + ' ' + AboutText());
  WriteLn()
 end { DoVersion } ;


(* GNU-mandated support for --version and --help.
*)
procedure DoHelp();

begin
  WriteLn();
  WriteLn('Usage: contec08a [OPTIONS]...');
  WriteLn();
  WriteLn('Output logged readings from a Contec08A veterinary sphygmomanometer.');
  WriteLn();
{$ifdef LCL }
  WriteLn('If there is no explicit option or device an interactive GUI screen will');
  WriteLn('be presented. Supported options are as below:');
{$else      }
  WriteLn('Supported options are as below:');
{$endif LCL }
  WriteLn();
  WriteLn('  -V, --version');
  WriteLn('        Version information.');
  WriteLn();
  WriteLn('  -H, --help');
  WriteLn('        This help text.');
  WriteLn();
  WriteLn('  -u NUM');
  WriteLn('        Recover data for user NUM, in the range 1..3.');
//  WriteLn('        As a special case, 0 will recover data for all users.');
  WriteLn();
  WriteLn('  -1');
  WriteLn('        Recover data for user 1, this is the default.');
  WriteLn();
  WriteLn('  -2');
  WriteLn('        Recover data for user 2.');
  WriteLn();
  WriteLn('  -3');
  WriteLn('        Recover data for user 3.');
//  WriteLn();
//  WriteLn('  -0');
//  WriteLn('        Recover data for all users.');
  WriteLn();
  WriteLn('  -v [NUM]');
  WriteLn('        Without a value, increment the verbosity. With a value, set the');
  WriteLn('        verbosity to that level. Assume that the default verbosity is 1.');
  WriteLn();
  WriteLn('  -q');
  WriteLn('        Decrement the verbosity, allowing it to be reduced to zero.');
  WriteLn();
  WriteLn('  -d [NUM]');
  WriteLn('        Without a value, increment the debugging level. With a value, set the');
  WriteLn('        debugging to that level. Assume that the default debugging level is 0.');
  WriteLn();
{$ifdef LCL }
  WriteLn('  -              Dummy option, ignored.');
{$else      }
  WriteLn('  - --           Dummy options, ignored.');
{$endif LCL }
  WriteLn();
  WriteLn('Exit status:');
  WriteLn();
  WriteLn(' 0  Normal termination');
  WriteLn(' 1  Cannot parse device identifier');
  WriteLn(' 2  Named device cannot be opened');
  WriteLn(' 3  Named device is unresponsive');
  WriteLn(' 4  Data access error');
  WriteLn(' 5  Data format error');
  WriteLn(' 9  Bad command-line parameters');
  WriteLn()
end { DoHelp } ;


(* Return true if there is no parameter. This includes the case where the
  commandline ends with --, which under GNU conventions may be used to
  terminate a sequence of options.
*)
function NoParams(): boolean;

var
  i, j: integer;

begin
  result := false;
  if ParamCount() = 0 then begin
    result := true;

(* if the underlying file descriptor of OUTPUT is not the same as that of INPUT *)
(* then assume it has been redirected and treat it as a parameter with the      *)
(* intention of favouring text rather than GUI operation.                       *)

{ TODO : Is INPUT set strangely if for a program invoked from e.g. the GUI's menu? }

    if fpReadLink('/proc/' + IntToStr(GetProcessId()) + '/fd/1') <>
                        fpReadLink('/proc/' + IntToStr(GetProcessId()) + '/fd/0') then
      result := false;
  end else begin
    i := 1;
    while i <= ParamCount() do begin
      if i < ParamCount() then begin    (* Can refer to ParamStr(i + 1)         *)
        case ParamStr(i) of
          '-u': if (ParamStr(i + 1) <> '-0') and TryStrToInt(ParamStr(i + 1), j) then
                  if j in [0..3] then begin
                    GetUser := j;
                    i += 1
                  end else
                    exit(false);
          '-0':  GetUser := 0;
          '-1':  GetUser := 1;
          '-2':  GetUser := 2;
          '-3':  GetUser := 3;
          '-d': if (ParamStr(i + 1) <> '-0') and TryStrToInt(ParamStr(i + 1), j) and (j >= 0) then begin
                  Prolixity := j;
                  i += 1
                end else
                  Prolixity += 1;
          '-q': Verbosity -= 1;
          '-v': if (ParamStr(i + 1) <> '-0') and TryStrToInt(ParamStr(i + 1), j) and (j >= 0) then begin
                  Verbosity := j;
                  i += 1
                end else
                  Verbosity += 1;
        otherwise
          exit(false)
        end
      end else begin                      (* Cannot refer to ParamStr(i + 1) at end *)
        case ParamStr(i) of
          '-0':  GetUser := 0;
          '-1':  GetUser := 1;
          '-2':  GetUser := 2;
          '-3':  GetUser := 3;
          '-d': Prolixity += 1;
          '-q': Verbosity -= 1;
          '-v': Verbosity += 1
        otherwise
          exit(false)
        end
      end;
      i += 1
    end;
    if ParamStr(ParamCount()) = '-' then
      result := true
{$ifndef LCL }
    else
      if ParamStr(ParamCount()) = '--' then
        result := true
{$endif LCL  }
  end
end { NoParams } ;


(* Before reading or writing the HID device poll for any netlink messages       *)
(* indicating that it's been disconnected or reconnected, updating these        *)
(* variables.                                                                   *)

var
  savedHidPort: ansistring;
  savedHidFile: file of TContec08aBuffer;


(* Return the name of the HID device prefixed with /dev/ if it has been seen
  (typically at program startup) and not removed.
*)
function FindContec08aPort(): ansistring;

begin
  savedHidPort := PollDeviceAlreadyExists(Vid, Pid);
  if savedHidPort <> '' then
    savedHidPort := '/dev/' + savedHidPort;
  result := savedHidPort
end { FindContec08aPort } ;


(* This is the inner loop of the main function. If the final parameter is nil
  then output each decoded line using WriteLn(), otherwise call the indicated
  writer procedure which will typically send the output to the GUI.
*)
function RunConsoleApp2(var portFile: File; op: TOperation;
                        var pleaseStop: boolean; writer: TWriteLn= nil): integer;

begin result := 9 end {} ;


(* Main function, return 0 if no error.
*)
function RunConsoleApp(portName: string): integer;

label
  forEachUser;

var
  hidBuffer: TContec08aBuffer;
  byteCount, recordNum, lastRecord, userNum: integer;


  procedure dump;

  var
    i, j: integer;

  begin
    for i := 0 to 3 do begin
      Write(ErrOutput, HexStr(i * 16, 4));
      for j := 0 to 15 do begin
        if j mod 8 = 0 then
          Write(ErrOutput, ' ');
        Write(ErrOutput, ' ', HexStr(hidBuffer[i * 16 + j], 2))
      end;
      Write(ErrOutput, '  ');
      for j := 0 to 15 do
        if hidBuffer[i * 16 + j] in [$20..$7e] then
          Write(ErrOutput, Chr(hidBuffer[i * 16 + j]))
        else
          Write(ErrOutput, '·');
      WriteLn(ErrOutput)
    end;
    Flush(ErrOutput)
  end { dump } ;


begin
  if portname = '' then begin
    if Prolixity >= 0 then begin
      WriteLn(ErrOutput);
      WriteLn(ErrOutput, 'Device cannot be detected')
    end;
    exit(2)                             (* Cannot be opened (not plugged in)    *)
  end;
  Assign(savedHidFile, savedHidPort);
  Reset(savedHidFile);
  try

(* 0010                                    40 8f ff fe fd This from pcap/wireshark *)
(* 0020   fc 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00                       *)
(* 0030   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00                       *)
(* 0040   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00                       *)
(* 0050   00 00 00 00 00 00 00 00 00 00 00                                      *)

    FillByte(hidBuffer, 64, 0);
    hidBuffer[0] := $40;
    hidBuffer[1] := $8f;
    hidBuffer[2] := $ff;
    hidBuffer[3] := $fe;
    hidBuffer[4] := $fd;
    hidBuffer[5] := $fc;
    if Prolixity > 0 then begin
      WriteLn(ErrOutput, 'Sending');
      dump
    end;
    BlockWrite(savedHidFile, hidBuffer, 1, byteCount);

    FillByte(hidBuffer, 64, 0);
    BlockRead(savedHidFile, hidBuffer, 1, byteCount);
    if Prolixity > 0 then begin
      WriteLn(ErrOutput, 'Received');
      dump
    end;

(* 0010                                    40 8f ff fe fd This from pcap/wireshark *)
(* 0020   fc 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00                       *)
(* 0030   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00                       *)
(* 0040   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00                       *)
(* 0050   00 00 00 00 00 00 00 00 00 00 00                                      *)

    FillByte(hidBuffer, 64, 0);
    hidBuffer[0] := $40;
    hidBuffer[1] := $8f;
    hidBuffer[2] := $ff;
    hidBuffer[3] := $fe;
    hidBuffer[4] := $fd;
    hidBuffer[5] := $fc;
    if Prolixity > 0 then begin
      WriteLn(ErrOutput, 'Sending');
      dump
    end;
    BlockWrite(savedHidFile, hidBuffer, 1, byteCount);

    FillByte(hidBuffer, 64, 0);
    BlockRead(savedHidFile, hidBuffer, 1, byteCount);
    if Prolixity > 0 then begin
      WriteLn(ErrOutput, 'Received');
      dump
    end;

// Above: command 0x40 might just be a "ping".
// Below: command 0x42 might elicit a count of available records.
// Below: hence I tentatively speculate that 0x41 is a "clear archive" command.

(* 0010                                    42 8f ff fe fd This from pcap/wireshark *)
(* 0020   fc 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00                       *)
(* 0030   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00                       *)
(* 0040   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00                       *)
(* 0050   00 00 00 00 00 00 00 00 00 00 00                                      *)

    FillByte(hidBuffer, 64, 0);
    hidBuffer[0] := $42;
    hidBuffer[1] := $8f;
    hidBuffer[2] := $ff;
    hidBuffer[3] := $fe;
    hidBuffer[4] := $fd;
    hidBuffer[5] := $fc;
    if Prolixity > 0 then begin
      WriteLn(ErrOutput, 'Sending');
      dump
    end;
    BlockWrite(savedHidFile, hidBuffer, 1, byteCount);

    FillByte(hidBuffer, 64, 0);
    BlockRead(savedHidFile, hidBuffer, 1, byteCount);
    if Prolixity > 0 then begin
      WriteLn(ErrOutput, 'Received');
      dump
    end;

(* 0010                                    48 41 02 13 01 This from pcap/wireshark *)
(* 0020   02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00                       *)
(* 0030   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00                       *)
(* 0040   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00                       *)
(* 0050   00 00 00 00 00 00 00 00 00 00 00                                      *)

// Above: first byte in that block might be record count. Currently 0x48, 72
// records being received with the documented maximum being records 100 for
// each of three users.
// Below: command 0x43 elicits a download with records not needing to be acked/
// nacked and no explicit last-record marker. The first two records are a
// distinctive format which might not be relevant to this instrument, after
// which it settles down.

(* 0010                                    43 41 01 04 02 This from pcap/wireshark *)
(* 0020   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00                       *)
(* 0030   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00                       *)
(* 0040   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00                       *)
(* 0050   00 00 00 00 00 00 00 00 00 00 00                                      *)

    FillByte(hidBuffer, 64, 0);
    hidBuffer[0] := $43;
    hidBuffer[1] := $41;
    hidBuffer[2] := $01;
    if GetUser in [1..3] then
      hidBuffer[3] := $04 + (GetUser - 1)
    else
      hidBuffer[3] := $07;              (* All users                            *)
    hidBuffer[4] := $02;
    hidBuffer[5] := $00;
    if Prolixity > 0 then begin
      WriteLn(ErrOutput, 'Sending');
      dump
    end;
    BlockWrite(savedHidFile, hidBuffer, 1, byteCount);

(* Each user is documented as having up to 100 stored records, so including the *)
(* two leader records that's 102.                                               *)

(* I'm being coy about the -0 option to recover data for all three users, since *)
(* I could probably do with a more robust control flow than this goto.          *)

    if Verbosity > 0 then
      WriteLn('ID,Time,Date,SYS(mmHg),DIA(mmHg),PR(BPM),MAP(mmHg),PP(mmHg),TC,Comment,');
    recordNum := 1;
forEachUser:
    lastRecord := 102;
    while recordNum <= lastRecord do begin
      FillByte(hidBuffer, 64, 0);
      BlockRead(savedHidFile, hidBuffer, 1, byteCount);
      if Prolixity > 0 then begin
        WriteLn(ErrOutput, 'Received record ', recordNum, ' (', HexStr(recordNum, 4), ')');
        dump
      end;
      case recordNum of
        1: if hidBuffer[$0002] <> $01 then begin
             if Prolixity >= 0 then begin
               WriteLn(ErrOutput);
               WriteLn(ErrOutput, 'Device is turned off')
             end;
             Exit(3)                    (* Unresponsive (turned off)            *)
           end;
        2: begin
             lastRecord := 2 + (hidBuffer[4] and $7f);
             userNum := hidBuffer[13] and $03;
             if Prolixity > 0 then
               WriteLn(ErrOutput, 'User ', userNum, ', expecting ', lastRecord,
                                ' (', HexStr(lastRecord, 4), ') records total')
           end
      otherwise
        if Verbosity > 0 then begin
          Write(Format('%D+,%0.2D:%0.2D,', [recordNum - 2, hidBuffer[$000a] and $7f, hidBuffer[$000b] and $7f]));
          Write(Format('%0.2D-%0.2D-%4D,', [hidBuffer[$0009] and $7f, hidBuffer[$0007] and $7f, (hidBuffer[$0006] and $7f) + 2000]));
          Write(Format('%D,', [hidBuffer[$0002]]));     (* SYS          *)
          Write(Format('%D,', [hidBuffer[$0003] and $7f]));     (* DIA          *)
          Write(Format('%D,', [hidBuffer[$0004] and $7f]));     (* PR           *)
          Write(Format('%D,', [hidBuffer[$0005] and $7f]));     (* MAP          *)
          Write(Format('%D,', [hidBuffer[$0002] - (hidBuffer[$0003] and $7f)]));
          Write('0/1,');                (* Above is PP computed as SYS - DIA    *)
          WriteLn('User ', userNum, ',')
        end
      end;
      recordNum += 1
    end;
    if (GetUser = 0) and (userNum < 3) then begin
      recordNum := 2;
      goto forEachUser
    end
  finally
    CloseFile(savedHidFile)
  end;
  result := 0
end { RunConsoleApp } ;


begin
  Assert(FileMode = 2);                 (* Reset() opens files R/W              *)
  Assert(Format('%0.2D', [1]) = '01');  (* Relying on this for times            *)
  TFileRec(savedHidFile).mode := fmClosed
end.


{

Manual says limit 100 records for (each of?) three users.

Send

0010                                    42 8f ff fe fd
0020   fc 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00

Receive

0010                                    48 41 02 13 01
0020   02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00

Send
                                                  v======== user 1 out of 1..3
0010                                    43 41 01 04 02
0020   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00

Receive

0010                                    4a 43 01 00 00
0020   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00

0010                                    46 41 80 80 c6 <=== 0x46 (70) records???
0020   82 80 80 80 80 80 80 80 81 00 00 00 00 00 00 00
                                ^========================== 0x01 user 1 out of 1..3
0010                                    82 80 94 d5 c8
0020   e9 97 85 80 81 8d 89 80 91 00 00 00 00 00 00 00

0010                                    82 80 92 d6 ba
0020   f1 97 85 80 82 8a 85 80 91 00 00 00 00 00 00 00

0010                                    82 80 87 d5 c8
0020   e5 97 85 80 82 8d ab 80 91 00 00 00 00 00 00 00

0010                                    82 80 8a d4 c2
0020   eb 97 85 80 83 8b 84 80 91 00 00 00 00 00 00 00
...

From .csv file:

ID,Time,Date,SYS(mmHg),DIA(mmHg),PR(BPM),MAP(mmHg),PP(mmHg),TC,Comment,
1+,13:09,01-05-2023,148,85,72,105,63,0/1,
2+,10:05,02-05-2023,146,86,58,113,60,0/1,
3+,13:43,02-05-2023,135,85,72,101,50,0/1,
4+,11:04,03-05-2023,138,84,66,107,54,0/1,
...

From .awp file:

[PATIENT DATA]
Name=num1
ID=01
Test Count=1
[TEST 1]
DeviceType=65
ProtocolVersion=19
IsDisplay=1
AutoMode=1
AwakeHour=0
AwakeMin=0
AwakeDuration=0
AsleepHour=0
AsleepMin=0
AsleepDuration=0
SpecialHourStart=-1
SpecialMinStart=-1
SpecialDuration=0
SpecialHourEnd=-1
SpecialMinEnd=-1
TimePeriod=0
TestBeginDate=1/5/2023 13:09
YearBegin=2023
MonthBegin=5
DayBegin=1
HourBegin=13
MinBegin=9
Awake Time=0
Asleep Time=0
1=07E705010D090000940055006900480001000000010
C1=
2=07E705020A0500009200560071003A0001000000010
C2=
3=07E705020D2B0000870055006500480001000000010
C3=
4=07E705030B0400008A0054006B00420001000000010
C4=
...

Looking at first four data records in various formats:

0010   82 80 | 94 | d5 | c8 | e9 | 97 85 80 81 | 8d 89 | 80 91 00 00

0010   82 80 | 92 | d6 | ba | f1 | 97 85 80 82 | 8a 85 | 80 91 00 00

0010   82 80 | 87 | d5 | c8 | e5 | 97 85 80 82 | 8d ab | 80 91 00 00

0010   82 80 | 8a | d4 | c2 | eb | 97 85 80 83 | 8b 84 | 80 91 00 00

ID,Time,Date,SYS(mmHg),DIA(mmHg),PR(BPM),MAP(mmHg),PP(mmHg),TC,Comment,
1+,13:09,01-05-2023, | 148, | 85, | 72, | 105, | 63,0/1,
2+,10:05,02-05-2023, | 146, | 86, | 58, | 113, | 60,0/1,
3+,13:43,02-05-2023, | 135, | 85, | 72, | 101, | 50,0/1,
4+,11:04,03-05-2023, | 138, | 84, | 66, | 107, | 54,0/1,

1=07E705010D090000 | 9400 | 5500 | 6900480001000000010
C1=
2=07E705020A050000 | 9200 | 5600 | 71003A0001000000010
C2=
3=07E705020D2B0000 | 8700 | 5500 | 6500480001000000010
C3=
4=07E705030B040000 | 8A00 | 5400 | 6B00420001000000010
C4=

SYS and DIA work out fairly nicely, although I don't know whether to assume
big- or little-endian in the .awp file. PR comes from the hex but I can't see
it in the .awp. Ditto MAP. In the hex, MAP is followed by a 4-byte date and
2-byte time both of which suggests that at least the firmware favours big-
endian ordering. I think PP is a guess based on the non-connected SpO2 finger
sensor, but need to check.

Is MAP atmospheric pressure biased by 900? I think I've seen met charts do that.

No, "Mean Arterial Pressure" (which is not a simple average). PP is Pulse
Pressure i.e. difference between SYS and DIA,

01-05-2023  97 85 80 81  Year relative to 2006? Not sure about extra digit.
13:09  8d 89             24-hour clock.

02-05-2023  97 85 80 82
10:05  8a 85

02-05-2023  97 85 80 82
13:43  8d ab

03-05-2023  97 85 80 83
11:04  8b 84

82 80 94 db c0 f1 99 81 80 9c 8c 88 80 91 00 00

82 80 9d d9 c3 fb 99 83 80 94 8c 90 80 91 00 00

82 80 90 dc c1 f7 99 85 80 8f 8a 96 80 91 00 00

82 80 80 d0 bd e2 99 87 80 8f 8a 81 80 91 00 00

67+,12:08,28-01-2025,148,91,64,113,57,0/1,
68+,12:16,20-03-2025,157,89,67,123,68,0/1,
69+,10:22,15-05-2025,144,92,65,119,52,0/1,
70+,10:01,15-07-2025,128,80,61,98,48,0/1,

99 81 80 9c             0x19 -> 25 0x01 -> 1 0x00 -> 0 0x1c -> 28
8c 88
80 91 00 00

99 83 80 94             2025-03-20
8c 90
80 91 00 00

99 85 80 8f             2025-05-15
8a 96
80 91 00 00

99 87 80 8f             2025-07-15
8a 81
80 91 00 00

.awp reader at https://github.com/obidose/abpm50ex/tree/master but I don't see
it as being particularly relevant unless somebody demands that this program
create that type of file.

}






