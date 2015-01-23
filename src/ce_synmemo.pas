unit ce_synmemo;

{$I ce_defines.inc}

interface

uses
  Classes, SysUtils, SynEdit, ce_d2syn, ce_txtsyn ,SynEditHighlighter, controls,
  lcltype, LazSynEditText, SynEditKeyCmds, SynHighlighterLFM, SynEditMouseCmds,
  SynEditFoldedView, crc, ce_common, ce_observer, ce_writableComponent;

type

  TCESynMemo = class;

  TCEFoldCache = class(TCollectionItem)
  private
    fCollapsed: boolean;
    fLineIndex: Integer;
    fNestedIndex: Integer;
  published
    property isCollapsed: boolean read fCollapsed write fCollapsed;
    property lineIndex: Integer read fLineIndex write fLineIndex;
    property nestedIndex: Integer read fNestedIndex write fNestedIndex;
  end;

  TCESynMemoCache = class(TWritableLfmTextComponent)
  private
    fMemo: TCESynMemo;
    fFolds: TCollection;
    fCaretPosition: Integer;
    fSelectionEnd: Integer;
    fFontSize: Integer;
    fSourceFilename: string;
    procedure setFolds(someFolds: TCollection);
  published
    property caretPosition: Integer read fCaretPosition write fCaretPosition;
    property sourceFilename: string read fSourceFilename write fSourceFilename;
    property folds: TCollection read fFolds write setFolds;
    property selectionEnd: Integer read fSelectionEnd write fSelectionEnd;
    property fontSize: Integer read fFontSize write fFontSize;
  public
    constructor create(aComponent: TComponent); override;
    destructor destroy; override;
    //
    procedure beforeSave; override;
    procedure afterLoad; override;
    procedure save;
    procedure load;
  end;

  TCESynMemoPositions = class
  private
    fPos: Integer;
    fMax: Integer;
    fList: TFPList;
    fMemo: TCustomSynEdit;
  public
    constructor create(aMemo: TCustomSynEdit);
    destructor destroy; override;
    procedure store;
    procedure back;
    procedure next;
  end;

  TCESynMemo = class(TSynEdit)
  private
    fFilename: string;
    fModified: boolean;
    fFileDate: double;
    fIsDSource: boolean;
    fIsTxtFile: boolean;
    fIsConfig: boolean;
    fIdentifier: string;
    fTempFileName: string;
    fMultiDocSubject: TCECustomSubject;
    fStoredFontSize: Integer;
    fPositions: TCESynMemoPositions;
    fMousePos: TPoint;
    function getMouseStart: Integer;
    procedure changeNotify(Sender: TObject);
    procedure identifierToD2Syn;
    procedure saveCache;
    procedure loadCache;
  protected
    procedure SetVisible(Value: Boolean); override;
    procedure SetHighlighter(const Value: TSynCustomHighlighter); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyUp(var Key: Word; Shift: TShiftState); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y:Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y:Integer); override;
  public
    constructor Create(aOwner: TComponent); override;
    destructor destroy; override;
    procedure setFocus; override;
    //
    procedure checkFileDate;
    procedure loadFromFile(const aFilename: string);
    procedure saveToFile(const aFilename: string);
    procedure save;
    procedure saveTempFile;
    //
    property Identifier: string read fIdentifier;
    property fileName: string read fFilename;
    property modified: boolean read fModified;
    property tempFilename: string read fTempFileName;
    //
    property isDSource: boolean read fIsDSource;
    property isProjectSource: boolean read fIsConfig;
    property TextView;
    //
    property MouseStart: Integer read getMouseStart;
  end;

var
  D2Syn: TSynD2Syn;
  LfmSyn: TSynLfmSyn;
  TxtSyn: TSynTxtSyn;

implementation

uses
  graphics, ce_interfaces, ce_staticmacro, ce_dcd, SynEditHighlighterFoldBase;

{$REGION TCESynMemoCache -------------------------------------------------------}
constructor TCESynMemoCache.create(aComponent: TComponent);
begin
  inherited create(nil);
  if (aComponent is TCESynMemo) then
  fMemo := TCESynMemo(aComponent);
  fFolds := TCollection.Create(TCEFoldCache);
end;

destructor TCESynMemoCache.destroy;
begin
  fFolds.Free;
end;

procedure TCESynMemoCache.setFolds(someFolds: TCollection);
begin
  fFolds.Assign(someFolds);
end;

procedure TCESynMemoCache.beforeSave;
var
  i, start, prev: Integer;
  itm : TCEFoldCache;
begin
  if fMemo = nil then exit;
  //
  fCaretPosition := fMemo.SelStart;
  fSourceFilename := fMemo.fileName;
  fSelectionEnd := fMemo.SelEnd;
  fFontSize := fMemo.Font.Size;
  //
  // TODO-cEditor Cache: >nested< folding persistence
  // cf. other ways: http://forum.lazarus.freepascal.org/index.php?topic=26748.msg164722#msg164722
  prev := fMemo.Lines.Count-1;
  for i := fMemo.Lines.Count-1 downto 0 do
  begin
    // - CollapsedLineForFoldAtLine() does not handle the sub-folding.
    // - TextView visibility is increased so this is not the standard way of getting the infos.
    start := fMemo.TextView.CollapsedLineForFoldAtLine(i);
    if start = -1 then
      continue;
    if start = prev then
      continue;
    prev := start;
    itm := TCEFoldCache(fFolds.Add);
    itm.isCollapsed := true;
    itm.fLineIndex := start;
  end;
end;

procedure TCESynMemoCache.afterLoad;
var
  i: integer;
  itm : TCEFoldCache;
begin
  if fMemo = nil then exit;
  //
  if fFontSize > 0 then
    fMemo.Font.Size := fFontSize;
  // Currently collisions are not handled.
  if fMemo.fileName <> fSourceFilename then exit;
  //
  for i := 0 to fFolds.Count-1 do
  begin
    itm := TCEFoldCache(fFolds.Items[i]);
    if not itm.isCollapsed then
      continue;
    fMemo.TextView.FoldAtLine(itm.lineIndex-1);
  end;
  //
  fMemo.SelStart := fCaretPosition;
  fMemo.SelEnd := fSelectionEnd;
end;

{$IFDEF DEBUG}{$R-}{$ENDIF}
procedure TCESynMemoCache.save;
var
  fname: string;
  tempn: string;
  chksm: Cardinal;
begin
  tempn := fMemo.fileName;
  if not fileExists(tempn) then exit;
  //
  fname := getCoeditDocPath + 'editorcache' + DirectorySeparator;
  ForceDirectories(fname);
  chksm := crc32(0, nil, 0);
  chksm := crc32(chksm, @tempn[1], length(tempn));
  fname := fname + format('%.8X.txt', [chksm]);
  saveToFile(fname);
end;

procedure TCESynMemoCache.load;
var
  fname: string;
  tempn: string;
  chksm: Cardinal;
begin
  tempn := fMemo.fileName;
  if not fileExists(tempn) then exit;
  //
  fname := getCoeditDocPath + 'editorcache' + DirectorySeparator;
  chksm := crc32(0, nil, 0);
  chksm := crc32(chksm, @tempn[1], length(tempn));
  fname := fname + format('%.8X.txt', [chksm]);
  //
  if not fileExists(fname) then exit;
  loadFromFile(fname);
end;
{$IFDEF DEBUG}{$R+}{$ENDIF}
{$ENDREGION}

{$REGION TCESynMemoPositions ---------------------------------------------------}
constructor TCESynMemoPositions.create(aMemo: TCustomSynEdit);
begin
  fList := TFPList.Create;
  fMax  := 20;
  fMemo := aMemo;
  fPos  := -1;
end;

destructor TCESynMemoPositions.destroy;
begin
  fList.Free;
  inherited;
end;

procedure TCESynMemoPositions.back;
begin
  Inc(fPos);
  {$HINTS OFF}
  if fPos < fList.Count then
    fMemo.CaretY := NativeInt(fList.Items[fPos])
  {$HINTS ON}
  else Dec(fPos);
end;

procedure TCESynMemoPositions.next;
begin
  Dec(fPos);
  {$HINTS OFF}
  if fPos > -1 then
    fMemo.CaretY := NativeInt(fList.Items[fPos])
  {$HINTS ON}
  else Inc(fPos);
end;

procedure TCESynMemoPositions.store;
var
  delta: NativeInt;
const
  thresh = 6;
begin
  fPos := 0;
  {$HINTS OFF}{$WARNINGS OFF}
  if fList.Count > 0 then
  begin
    delta := fMemo.CaretY - NativeInt(fList.Items[fPos]);
    if (delta > -thresh) and (delta < thresh) then exit;
  end;
  fList.Insert(0, Pointer(NativeInt(fMemo.CaretY)));
  {$HINTS ON}{$WARNINGS ON}
  while fList.Count > fMax do
    fList.Delete(fList.Count-1);
end;
{$ENDREGION --------------------------------------------------------------------}

{$REGION TCESynMemo ------------------------------------------------------------}
constructor TCESynMemo.Create(aOwner: TComponent);
begin
  inherited;
  SetDefaultKeystrokes; // not called in inherited if owner = nil !
  Font.Quality := fqProof;
  //Font.CharSet := OEM_CHARSET;
  Font.Pitch := fpFixed;
  TabWidth := 4;
  BlockIndent := 4;
  Font.Size:= 10;
  Options :=
    [eoAutoIndent, eoBracketHighlight, eoGroupUndo, eoTabsToSpaces,
    eoDragDropEditing, eoShowCtrlMouseLinks, eoEnhanceHomeKey, eoTabIndent];
  Options2 :=
    [eoEnhanceEndKey, eoFoldedCopyPaste, eoOverwriteBlock];
  fStoredFontSize := Font.Size;

  MouseOptions := MouseOptions +
    [emAltSetsColumnMode, emDragDropEditing, emCtrlWheelZoom, emShowCtrlMouseLinks];
  Gutter.LineNumberPart.ShowOnlyLineNumbersMultiplesOf := 5;
  Gutter.LineNumberPart.MarkupInfo.Foreground := clGray;
  Gutter.SeparatorPart.LineOffset := 1;
  Gutter.SeparatorPart.LineWidth := 1;
  Gutter.SeparatorPart.MarkupInfo.Foreground := clGray;
  Gutter.CodeFoldPart.MarkupInfo.Foreground := clGray;
  BracketMatchColor.Foreground:=clRed;
  //
  MouseLinkColor.Style:= [fsUnderline];
  with MouseActions.Add do begin
    Command := emcMouseLink;
    shift := [ssCtrl];
    ShiftMask := [ssCtrl];
  end;
  //
  Highlighter := D2Syn;
  D2Syn.FoldKinds := [fkBrackets, fkComments1, fkComments2, fkStrings];
  //
  fTempFileName := GetTempDir(false) + 'temp_' + uniqueObjStr(self) + '.d';
  fFilename := '<new document>';
  fModified := false;
  ShowHint := true;
  TextBuffer.AddNotifyHandler(senrUndoRedoAdded, @changeNotify);
  //
  fPositions := TCESynMemoPositions.create(self);
  fMultiDocSubject := TCEMultiDocSubject.create;
  subjDocNew(TCEMultiDocSubject(fMultiDocSubject), self);
end;

destructor TCESynMemo.destroy;
begin
  saveCache;
  //
  subjDocClosing(TCEMultiDocSubject(fMultiDocSubject), self);
  fMultiDocSubject.Free;
  fPositions.Free;
  //
  if fileExists(fTempFileName) then
    sysutils.DeleteFile(fTempFileName);
  inherited;
end;

procedure TCESynMemo.setFocus;
begin
  inherited;
  checkFileDate;
  identifierToD2Syn;
  subjDocFocused(TCEMultiDocSubject(fMultiDocSubject), self);
end;

procedure TCESynMemo.SetVisible(Value: Boolean);
begin
  inherited;
  if Value then setFocus;
end;

procedure TCESynMemo.SetHighlighter(const Value: TSynCustomHighlighter);
begin
  inherited;
  fIsDSource := Highlighter = D2Syn;
  fIsConfig := Highlighter = LfmSyn;
  fIsTxtFile := Highlighter = TxtSyn;
end;

procedure TCESynMemo.identifierToD2Syn;
begin
  fIdentifier := GetWordAtRowCol(LogicalCaretXY);
  if fIsDSource then
    D2Syn.CurrentIdentifier := fIdentifier
  else if fIsTxtFile then
    TxtSyn.CurrIdent := fIdentifier;
end;

procedure TCESynMemo.changeNotify(Sender: TObject);
begin
  identifierToD2Syn;
  fModified := true;
  fPositions.store;
  subjDocChanged(TCEMultiDocSubject(fMultiDocSubject), self);
end;

procedure TCESynMemo.loadFromFile(const aFilename: string);
var
  ext: string;
begin
  ext := extractFileExt(aFilename);
  if dExtList.IndexOf(ext) = -1 then
    Highlighter := TxtSyn;
  Lines.LoadFromFile(aFilename);
  fFilename := aFilename;
  FileAge(fFilename, fFileDate);
  //
  loadCache;
  //
  fModified := false;
  setFocus;
  subjDocChanged(TCEMultiDocSubject(fMultiDocSubject), self);
end;

procedure TCESynMemo.saveToFile(const aFilename: string);
var
  ext: string;
begin
  Lines.SaveToFile(aFilename);
  fFilename := aFilename;
  ext := extractFileExt(aFilename);
  if dExtList.IndexOf(ext) <> -1 then
    Highlighter := D2Syn;
  FileAge(fFilename, fFileDate);
  fModified := false;
  if fFilename <> fTempFileName then
    subjDocChanged(TCEMultiDocSubject(fMultiDocSubject), self);
end;

procedure TCESynMemo.save;
begin
  Lines.SaveToFile(fFilename);
  FileAge(fFilename, fFileDate);
  fModified := false;
  if fFilename <> fTempFileName then
    subjDocChanged(TCEMultiDocSubject(fMultiDocSubject), self);
end;

procedure TCESynMemo.saveTempFile;
begin
  saveToFile(fTempFileName);
  fModified := false;
end;

procedure TCESynMemo.saveCache;
var
  cache: TCESynMemoCache;
begin
  cache := TCESynMemoCache.create(self);
  try
    cache.save;
  finally
    cache.free;
  end;
end;

procedure TCESynMemo.loadCache;
var
  cache: TCESynMemoCache;
begin
  cache := TCESynMemoCache.create(self);
  try
    cache.load;
  finally
    cache.free;
  end;
end;

procedure TCESynMemo.checkFileDate;
var
  newDate: double;
begin
  if fFilename = fTempFileName then exit;
  if not FileAge(fFilename, newDate) then exit;
  if fFileDate = newDate then exit;
  if fFileDate <> 0.0 then
  begin
    if dlgOkCancel(format('"%s" has been modified by another program, load the new version ?',
      [shortenPath(fFilename, 25)])) = mrOk then
    begin
      Lines.LoadFromFile(fFilename);
      fModified := false;
    end;
  end;
  fFileDate := newDate;
end;

procedure TCESynMemo.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  identifierToD2Syn;
  //
  if (Shift = [ssCtrl]) then case Key of
    VK_ADD: if Font.Size < 50 then Font.Size := Font.Size + 1;
    VK_SUBTRACT: if Font.Size > 3 then Font.Size := Font.Size - 1;
    VK_DECIMAL: Font.Size := fStoredFontSize;
  end;
end;

procedure TCESynMemo.KeyUp(var Key: Word; Shift: TShiftState);
begin
  if Key in [VK_PRIOR, VK_NEXT, Vk_UP] then
    fPositions.store;
  inherited;
  //
  if StaticEditorMacro.automatic then
    StaticEditorMacro.Execute;
end;

function TCESynMemo.getMouseStart: Integer;
var
  i, le: Integer;
begin
  result := 0;
  le := getLineEndingLength(fFilename);
  for i:= 0 to fMousePos.y-2 do
    result += length(Lines.Strings[i]) + le;
  result += fMousePos.x;
end;

procedure TCESynMemo.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if ssLeft in Shift then
    identifierToD2Syn;
  fMousePos := PixelsToRowColumn(Point(X,Y));
end;

procedure TCESynMemo.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y:Integer);
begin
  inherited;
  identifierToD2Syn;
end;

procedure TCESynMemo.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y:Integer);
begin
  inherited;
  if (Button = mbMiddle) and (Shift = [ssCtrl]) then
    Font.Size := fStoredFontSize
  else if Button = mbExtra1 then
    fPositions.back
  else if Button = mbExtra2 then
    fPositions.next
  else if Button = mbLeft then
    fPositions.store;
end;
{$ENDREGION --------------------------------------------------------------------}

initialization
  D2Syn := TSynD2Syn.create(nil);
  LfmSyn := TSynLFMSyn.Create(nil);
  TxtSyn := TSynTxtSyn.create(nil);
  //
  LfmSyn.KeyAttri.Foreground := clNavy;
  LfmSyn.KeyAttri.Style := [fsBold];
  LfmSyn.NumberAttri.Foreground := clMaroon;
  LfmSyn.StringAttri.Foreground := clBlue;
finalization
  D2Syn.Free;
  LfmSyn.Free;
  TxtSyn.Free;
end.
