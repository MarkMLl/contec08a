(* Lazarus+FPC 2.2.6+3.2.2 on Linux Lazarus+FPC 2.2.6+3.2.2 on Linux Lazarus+FP *)

program Contec08a;

(* Collect data from a Contec08A sphygmomanometer, intended for veterinary use. *)
(* This is highly experimental, the data is partially (where at all) decoded    *)
(* and there is no support at all for the SpO2 accessory.       MarkMLl.        *)

{$mode objfpc}{$H+}

uses
{$ifdef LCL }
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, Forms, Contec08aCode,
{$endif LCL }
  ConsoleApp;

var
  contec08Port: ansistring= '';
  i: integer;

{$ifdef LCL }

(* Note the conditional compilation here specifically to support "old-style"    *)
(* resources etc. as used by a pre-v1 Lazarus typically with a pre-v2.4 FPC. In *)
(* practice that means FPC 2.2.4, since no attempt is made to support older     *)
(* versions due to their lack of the FPC_FULLVERSION predefined.                *)

{$if FPC_FULLVERSION >= 020400 }
  {$R *.res}
{$endif FPC_FULLVERSION        }
{$endif LCL }

begin
  for i := 1 to ParamCount() do
    case ParamStr(i) of
      '-V',
      '/v',
      '/V',
      '--version': begin
                     DoVersion('Contec08A');
                     Halt(0)
                   end
    otherwise
    end;
  Contec08Port := FindContec08aPort();
  for i := 1 to ParamCount() do
    case ParamStr(i) of
      '-H',
      '/h',
      '/H',
      '--help': begin
                  DoHelp();
                  Halt(0)
                end
    otherwise
    end;
{$ifdef LCL }
  if not NoParams() then    (* If GUI is available, activated by any parameter  *)
{$endif LCL }
    Halt(RunConsoleApp(contec08Port));

(* The objective here is to minimise the amount of manually-inserted text so as *)
(* to give the IDE the best chance of managing form names etc. automatically. I *)
(* try, I don't always succeed...                                               *)

{$ifdef LCL }

(* Lazarus v1 (roughly corresponding to FPC 3.0) introduced this global         *)
(* variable, defaulting to false. It controls error reporting at startup if an  *)
(* expected .lfm is missing, so may be omitted if unsupported by the target LCL *)
(* etc. version e.g. by using the test $if LCL_FULLVERSION >= 1000000...$ifend. *)

{$if declared(RequireDerivedFormResource) }
  RequireDerivedFormResource:=True;
{$endif declared                          }

(* Lazarus v2 or later might insert  Application.Scaled := true  here if the    *)
(* project-level application settings include "Use LCL scaling". If required    *)
(* guard using the test $if LCL_FULLVERSION >= 1080000...$ifend.                *)

  Application.Scaled:=True;
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
{$endif LCL }
end.

