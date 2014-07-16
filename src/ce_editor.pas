unit ce_editor;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, ExtendedNotebook, Forms, Controls, lcltype,
  Graphics, SynEditKeyCmds, ComCtrls, SynEditHighlighter, ExtCtrls, Menus,
  SynEditHighlighterFoldBase, SynMacroRecorder, SynPluginSyncroEdit, SynEdit,
  SynHighlighterLFM, ce_widget, ce_d2syn, ce_synmemo, ce_common, AnchorDocking,
  ce_dlang, ce_project;

type
  { TCEEditorWidget }
  TCEEditorWidget = class(TCEWidget)
    imgList: TImageList;
    PageControl: TExtendedNotebook;
    macRecorder: TSynMacroRecorder;
    editorStatus: TStatusBar;
    procedure PageControlChange(Sender: TObject);
    procedure PageControlCloseTabClicked(Sender: TObject);
  protected
    procedure UpdateByDelay; override;
    procedure UpdateByEvent; override;
  private
    fKeyChanged: boolean;

    // http://bugs.freepascal.org/view.php?id=26329
    fSyncEdit: TSynPluginSyncroEdit;

    tokLst: TLexTokenList;
    errLst: TLexErrorList;
    procedure memoKeyPress(Sender: TObject; var Key: char);
    procedure memoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure memoMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure memoChange(Sender: TObject);
    procedure memoMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    function getCurrentEditor: TCESynMemo;
    function getEditor(index: NativeInt): TCESynMemo;
    function getEditorCount: NativeInt;
    function getEditorIndex: NativeInt;
    procedure identifierToD2Syn(const aMemo: TCESynMemo);
  public
    constructor create(aOwner: TComponent); override;
    destructor destroy; override;
    procedure addEditor;
    procedure removeEditor(const aIndex: NativeInt);
    procedure focusedEditorChanged;
    //
    procedure projCompile(const aProject: TCEProject); override;
    procedure projRun(const aProject: TCEProject); override;
    //
    property currentEditor: TCESynMemo read getCurrentEditor;
    property editor[index: NativeInt]: TCESynMemo read getEditor;
    property editorCount: NativeInt read getEditorCount;
    property editorIndex: NativeInt read getEditorIndex;
  end;

implementation
{$R *.lfm}

uses
  ce_main, ce_messages;

constructor TCEEditorWidget.create(aOwner: TComponent);
var
  bmp: TBitmap;
begin
  inherited;
  fID := 'ID_EDIT';
  //
  tokLst := TLexTokenList.Create;
  errLst := TLexErrorList.Create;
  //
  fSyncEdit := TSynPluginSyncroEdit.Create(self);
  bmp := TBitmap.Create;
  try
    imgList.GetBitmap(0,bmp);
    fSyncEdit.GutterGlyph.Assign(bmp);
  finally
    bmp.Free;
  end;
  DockMaster.GetAnchorSite(Self).Name := ID;
end;

destructor TCEEditorWidget.destroy;
begin
  tokLst.Free;
  errLst.Free;
  inherited;
end;

function TCEEditorWidget.getEditorCount: NativeInt;
begin
  result := pageControl.PageCount;
end;

function TCEEditorWidget.getEditorIndex: NativeInt;
begin
  if pageControl.PageCount > 0 then
    result := pageControl.PageIndex
  else result := -1;
end;

function TCEEditorWidget.getCurrentEditor: TCESynMemo;
begin
  if pageControl.PageCount = 0 then result := nil
  else result := TCESynMemo(pageControl.ActivePage.Controls[0]);
end;

function TCEEditorWidget.getEditor(index: NativeInt): TCESynMemo;
begin
  result := TCESynMemo(pageControl.Pages[index].Controls[0]);
end;

procedure TCEEditorWidget.focusedEditorChanged;
var
  curr: TCESynMemo;
begin
  curr := getCurrentEditor;
  macRecorder.Editor := curr;
  fSyncEdit.Editor := curr;
  if curr <> nil then
  begin
    identifierToD2Syn(curr);
    curr.checkFileDate;
  end;
  //
  if pageControl.ActivePageIndex <> -1 then
    mainForm.docFocusedNotify(Self, pageControl.ActivePageIndex);
  //
  if (pageControl.ActivePage.Caption = '') then
  begin
    fKeyChanged := true;
    beginUpdateByDelay;
  end;
end;

procedure TCEEditorWidget.PageControlChange(Sender: TObject);
begin
  //http://bugs.freepascal.org/view.php?id=26320
  focusedEditorChanged;
end;

procedure TCEEditorWidget.PageControlCloseTabClicked(Sender: TObject);
begin
  // closeBtn not implemented
  mainForm.actFileClose.Execute;
end;

procedure TCEEditorWidget.addEditor;
var
  sheet: TTabSheet;
  memo: TCESynMemo;
begin
  sheet := pageControl.AddTabSheet;
  memo  := TCESynMemo.Create(sheet);
  //
  memo.Align:=alClient;
  memo.Parent := sheet;
  //
  memo.OnKeyDown := @memoKeyDown;
  memo.OnKeyUp := @memoKeyDown;
  memo.OnKeyPress := @memoKeyPress;
  memo.OnMouseDown := @memoMouseDown;
  memo.OnChange := @memoChange;
  memo.OnMouseMove := @memoMouseMove;
  //
  pageControl.ActivePage := sheet;

  //http://bugs.freepascal.org/view.php?id=26320
  focusedEditorChanged;
end;

procedure TCEEditorWidget.removeEditor(const aIndex: NativeInt);
begin
  mainForm.MessageWidget.ClearMessages(msEditor);
  editor[aIndex].OnChange:= nil;
  pageControl.Pages[aIndex].Free;
end;

procedure TCEEditorWidget.identifierToD2Syn(const aMemo: TCESynMemo);
begin
  D2Syn.CurrentIdentifier := aMemo.GetWordAtRowCol(aMemo.LogicalCaretXY);
end;

procedure TCEEditorWidget.memoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  UpdateByEvent;
  if (sender is TCESynMemo) then
    identifierToD2Syn(TCESynMemo(Sender));
  case Byte(Key) of
    VK_CLEAR,VK_RETURN,VK_BACK : fKeyChanged := true;
    //else fKeyChanged := false;
  end;
  if fKeyChanged then
    beginUpdateByDelay;
end;

procedure TCEEditorWidget.memoKeyPress(Sender: TObject; var Key: char);
begin
  fKeyChanged := true;
  beginUpdateByDelay;
end;

procedure TCEEditorWidget.memoMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (sender is TCESynMemo) then
    identifierToD2Syn(TCESynMemo(Sender));
  beginUpdateByDelay;
  UpdateByEvent;
end;

procedure TCEEditorWidget.memoMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if not (ssLeft in Shift) then exit;
  //
  beginUpdateByDelay;
  UpdateByEvent;
end;

procedure TCEEditorWidget.memoChange(Sender: TObject);
var
  ed: TCESynMemo;
begin
  ed := TCESynMemo(sender);
  ed.modified := true;
  fKeyChanged := true;
  beginUpdateByDelay;
  UpdateByEvent;
end;

procedure TCEEditorWidget.projCompile(const aProject: TCEProject);
begin
  stopUpdateByDelay;
end;

procedure TCEEditorWidget.projRun(const aProject: TCEProject);
begin
  stopUpdateByDelay;
end;

procedure TCEEditorWidget.UpdateByEvent;
const
  modstr: array[boolean] of string = ('...', 'MODIFIED');
var
  ed: TCESynMemo;
begin
  ed := getCurrentEditor;
  if ed = nil then exit;
  //
  editorStatus.Panels[0].Text := format('%d : %d',[ed.CaretY, ed.CaretX]);
  editorStatus.Panels[1].Text := modstr[ed.modified];
  editorStatus.Panels[2].Text := ed.fileName;
end;

procedure TCEEditorWidget.UpdateByDelay;
var
  ed: TCESynMemo;
  err: TLexError;
  md: string;
begin
  ed := getCurrentEditor;
  if ed = nil then exit;
  if not fKeyChanged then exit;
  //
  fKeyChanged := false;
  mainForm.docChangeNotify(Self, editorIndex);
  if ed.Lines.Count = 0 then exit;
  //
  mainForm.MessageWidget.ClearMessages(msEditor);
  lex( ed.Lines.Text, tokLst );

  checkSyntacticErrors( tokLst, errLst);
  for err in errLst do
    mainForm.MessageWidget.addMessage(format( '%s  (@line:%4.d @char:%.4d)',
    [err.msg, err.position.y, err.position.x]), msEditor);

  md := '';
  if ed.isDSource then
    md := getModuleName(tokLst);
  if md = '' then md := extractFileName(ed.fileName);
  pageControl.ActivePage.Caption := md;

  mainForm.MessageWidget.scrollToBack;
  tokLst.Clear;
  errLst.Clear;
end;

end.

