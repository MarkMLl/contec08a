(* Lazarus+FPC 2.2.6+3.2.2 on Linux Lazarus+FPC 2.2.6+3.2.2 on Linux Lazarus+FP *)

unit MonitorHidLinux;

(* These are support routines intended to allow the program to work properly    *)
(* irrespective of whether the device is present at startup, or whether it is   *)
(* hotplugged after startup. In either case the name is deduced automatically   *)
(* based on the USB device identifier.                          MarkMLl         *)

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

var
  DumpNow: boolean= false;

(* At program startup, examine /sys/bus/hid/devices looking for a subdirectory
  named like *:1941:8021.* . In this expect a directory hidraw, in which there
  should be a directory such as hidraw5: return this name without embellishment.
*)
function PollDeviceAlreadyExists(vid, pid: word): ansistring;

(* Push a minimal add message for an hidraw device, returning false if this
  must be retried. The parameter must be e.g. hidraw5 with an optional /dev
  prefix.
*)
function PushDeviceAddition(vid, pid: word; const devname: ansistring): boolean;

(* Push a minimal remove message for an hidraw device, returning false if this
  must be retried. The parameter must be e.g. hidraw5 with an optional /dev
  prefix.
*)
function PushDeviceRemoval(vid, pid: word; const devname: ansistring): boolean;

(* Prior to normal operation, poll for the addition of the expected HID device,
  either because it was present at program startup (see above) or because it's
  been hotplugged. If not present then return an empty string, otherwise return
  e.g. /dev/hidraw5.
*)
function PollDeviceAddition(vid, pid: word): ansistring;

(* During normal operation, poll for device removal returning the device name
  e.g. /dev/hidraw5 if this appears to have happened.
*)
function PollDeviceRemoval(vid, pid: word): ansistring;


implementation

uses
  StrUtils, RegExpr, BaseUnix, Errors, LocatePorts;


(* Expand unsupported character classes.
*)
function unPosix(const pattern: ansistring): ansistring;

begin
  result := AnsiReplaceStr(pattern, '[:xdigit:]', '[0-9A-Fa-f]')
end { unPosix } ;


(* At program startup, examine /sys/bus/hid/devices looking for a subdirectory
  named like *:1941:8021.* . In this expect a directory hidraw, in which there
  should be a directory such as hidraw5: return this name without embellishment.
*)
function PollDeviceAlreadyExists(vid, pid: word): ansistring;

const
  path= '/sys/bus/hid/devices';

var
  searchRec: TRawbyteSearchRec;
  regex: TRegExpr;
  dir: rawbytestring= '';

begin
  result := '';
  regex := TRegExpr.Create;
  try
    regex.Expression := unPosix(Format('^[:xdigit:]{4}:%.4X:%.4X\.[:xdigit:]{4}$', [vid, pid]));
    if FindFirst(path + '/' + '*', faDirectory, searchRec) = 0 then
      try
        repeat
          if regex.Exec(searchRec.name) then begin
            dir := path + '/' + searchRec.name;
            break
          end
        until FindNext(searchRec) <> 0;
      finally
        findClose(searchRec)
      end;
    if dir <> '' then begin
      dir += '/hidraw';
      if DirectoryExists(dir) then
        if FindFirst(dir + '/' + 'hidraw*', faDirectory, searchRec) = 0 then begin
          result := searchRec.name;
          findClose(searchRec)
        end
    end
  finally
    FreeAndNil(regex)
  end
end { PollDeviceAlreadyExists } ;


(* Push a minimal addition or removal message for an hidraw device, returning
  false if this must be retried. The parameter must be e.g. hidraw5 with an
  optional /dev prefix.
*)
function pushDeviceAddOrRemove(const action: ansistring; vid, pid: word;
                                                devname: ansistring): boolean;

var
  sl: TStringList;

begin
  if Pos('/dev/', devName) > 0 then
    Delete(devName, 1, Length('/dev/'));
  sl := TStringList.Create;
  try
    sl.Append('message=' + action + '@/--');
    sl.Append('ACTION=' + action);
    sl.Append('SUBSYSTEM=hidraw');

(* This string should approximate the pattern /devices/pci0000:00/0000:00:14.0/ *)
(* usb1/1-9/1-9:1.0/0003:1941:8021.002E/hidraw/hidraw5                          *)

    sl.Append(Format('DEVPATH=---:%.4X:%.4X.0000/hidraw/%S', [vid, pid, devName]));
    sl.Append('DEVNAME=' + devName);
    result := PushHotplugEventParsed(sl)
  finally
    FreeAndNil(sl)
  end
end { pushDeviceAddOrRemove } ;


(* Push a minimal add message for an hidraw device, returning false if this
  must be retried. The parameter must be e.g. hidraw5 with an optional /dev
  prefix.
*)
function PushDeviceAddition(vid, pid: word; const devname: ansistring): boolean;

var
  addition: TStringList;

begin
  result := pushDeviceAddOrRemove('add', vid, pid, devName)
end { PushDeviceAddition } ;


(* Push a minimal remove message for an hidraw device, returning false if this
  must be retried. The parameter must be e.g. hidraw5 with an optional /dev
  prefix.
*)
function PushDeviceRemoval(vid, pid: word; const devname: ansistring): boolean;

var
  removal: TStringList;

begin
  result := pushDeviceAddOrRemove('remove', vid, pid, devName)
end { PushDeviceRemoval } ;


(* During normal operation, poll for device removal returning the device name
  e.g. /dev/hidraw5 if this appears to have happened.
*)
function pollDeviceAdditionOrRemoval(const action: ansistring; vid, pid: word): ansistring;

var
  hotplugEvent: TStringList;
  regex: TRegExpr;

begin
  result := '';
  hotplugEvent := ParseHotplugEvent(PollHotplugEventUnparsed());
  if hotplugEvent = nil then
    exit('');
  if hotplugEvent.Values['ACTION'] <> 'add' then
    exit('');
  if hotplugEvent.Values['SUBSYSTEM'] <> 'hidraw' then
    exit('');
  regex := TRegExpr.Create;
  try

(* This should match a substring of the pattern /devices/pci0000:00/0000:00:14. *)
(* 0/usb1/1-9/1-9:1.0/0003:1941:8021.002E/hidraw/hidraw5                        *)

    regex.Expression := unPosix(Format('^.*:%.4X:%.4X\.[:xdigit:]{4}/hidraw/hidraw\d+$', [vid, pid]));
    if regex.Exec(hotplugEvent.Values['DEVPATH']) then
      result := '/dev/' + hotplugEvent.Values['DEVNAME']
  finally
    FreeAndNil(regex)
  end
end { pollDeviceAdditionOrRemoval } ;


(* Prior to normal operation, poll for the addition of the expected HID device,
  either because it was present at program startup (see above) or because it's
  been hotplugged. If not present then return an empty string, otherwise return
  e.g. /dev/hidraw5.
*)
function PollDeviceAddition(vid, pid: word): ansistring;

var
  hotplugEvent: TStringList;
  regex: TRegExpr;

begin
  result := pollDeviceAdditionOrRemoval('add', vid, pid)
end { PollDeviceAddition } ;


(* During normal operation, poll for device removal returning the device name
  e.g. /dev/hidraw5 if this appears to have happened.
*)
function PollDeviceRemoval(vid, pid: word): ansistring;

var
  hotplugEvent: TStringList;
  regex: TRegExpr;

begin
  result := pollDeviceAdditionOrRemoval('remove', vid, pid)
end { PollDeviceRemoval } ;


(* Signal handling is in this unit since, like most of the hotplugging stuff,   *)
(* it's very much OS-specific.                                                  *)


(* We don't ever want to screw the MCP by responding to a casual ^C. We do,
  however, want to do our best to shut down in good order if we get an urgent
  signal such as SIGTERM, since it might indicate an incipient power failure.

  As a general point, note that the if the shell implements kill functionality
  this probably won't support the required -q option to pass a parameter with
  SI_QUEUE, use /usr/bin/kill instead.

  Note that this might not work as expected if run under a debugger.
*)
procedure termHandler(sig: longint; info: PSigInfo; context: PSigContext); cdecl;

const
  SI_USER=	0;		(* sent by kill, sigsend, raise *)
  SI_KERNEL=	$80;		(* sent by the kernel from somewhere *)
  SI_QUEUE=	-1;		(* sent by sigqueue *)
  SI_TIMER=	-2;		(* sent by timer expiration *)
  SI_MESGQ=	-3;		(* sent by real time mesq state change *)
  SI_ASYNCIO=	-4;		(* sent by AIO completion *)
  SI_SIGIO=	-5;		(* sent by queued SIGIO *)
  SI_TKILL=	-6;		(* sent by tkill system call *)
  SI_DETHREAD=	-7;		(* sent by execve() killing subsidiary threads *)
  SI_ASYNCNL=	-60;		(* sent by glibc async name lookup completion *)

begin
  case sig of
    SIGUSR1: DumpNow := true;
  otherwise
  end
end { termHandler } ;


(* We don't ever want to bomb on getting ^C (SIGINT) or ^\ (SIGQUIT).
*)
procedure catchsignals;

var     action: SigActionRec;

begin
  FillChar(action, SizeOf(action), 0);
  action.Sa_Handler := @termHandler;
  action.Sa_Flags := SA_SIGINFO;
  if fpSigAction(SIGUSR1, @action, nil) <> 0 then
    WriteLn(ErrOutput, 'Warning: SIGUSR1 not hooked, error ' + IntToStr(fpGetErrNo) + ', "' + StrError(fpGetErrNo) + '"', true)
end { catchSignals } ;


begin
  Assert(Length(Format('%4X', [1])) = 4);       (* Test %X width                *)
  Assert(Length(Format('%.4X', [1])) = 4);      (* Test %X precision            *)
  Assert(Length(Format('%0.4X', [1])) = 4);     (* Test %X precision            *)
  Assert(Format('%4X', [1])[1] = ' ');          (* %X width space-pads          *)
  Assert(Format('%.4X', [1])[1] = '0');         (* %X precision zero-pads       *)
  Assert(Format('%0.4X', [1])[1] = '0');        (* %X precision zero-pads       *)
  catchSignals
end.

