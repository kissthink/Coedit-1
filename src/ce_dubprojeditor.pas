unit ce_dubprojeditor;

{$I ce_defines.inc}

interface

uses
  Classes, SysUtils, FileUtil, TreeFilterEdit, Forms, Controls, Graphics,
  Dialogs, ExtCtrls, Menus, StdCtrls, Buttons, ComCtrls, jsonparser, fpjson,
  ce_widget, ce_common, ce_interfaces, ce_observer, ce_dubproject, ce_sharedres,
  ce_dsgncontrols, ce_dialogs;

type

  TProposalType = (ptArray, ptObject, ptValue);

  TEditorProposal = record
    name: string;
    jtype: TProposalType;
  end;


  TDubPropAddEvent = procedure(const propName: string; tpe: TJSONtype) of object;

  TCEDubProjectPropAddPanel = class(TForm)
  private
    fSelType: TRadioGroup;
    fEdName: TComboBox;
    fEvent: TDubPropAddEvent;
    fBtnValidate: TBitBtn;
    fJson: TJSONData;
    procedure doValidate(sender: TObject);
    procedure selTypeChanged(sender: TObject);
    procedure setSelFromProposal(sender: TObject);
  public
    constructor construct(event: TDubPropAddEvent; json: TJSONData);
  end;

  { TCEDubProjectEditorWidget }
  TCEDubProjectEditorWidget = class(TCEWidget, ICEProjectObserver)
    btnAcceptProp: TSpeedButton;
    btnAddProp: TCEToolButton;
    btnCloneObject: TCEToolButton;
    btnDelProp: TCEToolButton;
    btnUpdate: TCEToolButton;
    edProp: TEdit;
    fltEdit: TTreeFilterEdit;
    imgList: TImageList;
    MenuItem1: TMenuItem;
    Panel1: TPanel;
    propTree: TTreeView;
    procedure btnAcceptPropClick(Sender: TObject);
    procedure btnAddPropClick(Sender: TObject);
    procedure btnDelPropClick(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnCloneObjectClick(Sender: TObject);
    procedure MenuItem1Click(Sender: TObject);
    procedure propTreeSelectionChanged(Sender: TObject);
  private
    fSelectedNode: TTreeNode;
    fProj: TCEDubProject;
    procedure updateEditor;
    procedure updateValueEditor;
    procedure setJsonValueFromEditor;
    procedure addProp(const propName: string; tpe: TJSONtype);
    //
    procedure projNew(project: ICECommonProject);
    procedure projChanged(project: ICECommonProject);
    procedure projClosing(project: ICECommonProject);
    procedure projFocused(project: ICECommonProject);
    procedure projCompiling(project: ICECommonProject);
    procedure projCompiled(project: ICECommonProject; success: boolean);
    //
  protected
    procedure SetVisible(value: boolean); override;
    procedure setToolBarFlat(value: boolean); override;
  public
    constructor create(aOwner: TComponent); override;
  end;

implementation
{$R *.lfm}

const
  proposals: array[0..43] of TEditorProposal = (
    (name: 'authors';             jtype: ptArray),
    (name: 'buildOptions';        jtype: ptArray),
    (name: 'buildRequirements';   jtype: ptArray),
    (name: 'buildTypes';          jtype: ptObject),
    (name: 'configurations';      jtype: ptArray),
    (name: 'copyFiles';           jtype: ptArray),
    (name: 'copyright';           jtype: ptValue),
    (name: 'cov';                 jtype: ptArray),
    (name: 'ddoc';                jtype: ptArray),
    (name: 'ddoxFilterArgs';      jtype: ptArray),
    (name: 'debug';               jtype: ptArray),
    (name: 'debugVersions';       jtype: ptArray),
    (name: 'dependencies';        jtype: ptObject),
    (name: 'description';         jtype: ptValue),
    (name: 'dflags';              jtype: ptArray),
    (name: 'docs';                jtype: ptArray),
    (name: 'excludedSourceFiles'; jtype: ptArray),
    (name: 'homepage';            jtype: ptValue),
    (name: 'lflags';              jtype: ptArray),
    (name: 'libs';                jtype: ptArray),
    (name: 'license';             jtype: ptValue),
    (name: 'mainSourceFile';      jtype: ptValue),
    (name: 'name';                jtype: ptValue),
    (name: 'plain';               jtype: ptArray),
    (name: 'platforms';           jtype: ptArray),
    (name: 'postBuildCommands';   jtype: ptArray),
    (name: 'postGenerateCommands';jtype: ptArray),
    (name: 'preBuildCommands';    jtype: ptArray),
    (name: 'preGenerateCommands'; jtype: ptArray),
    (name: 'profile';             jtype: ptArray),
    (name: 'release';             jtype: ptArray),
    (name: 'sourceFiles';         jtype: ptArray),
    (name: 'sourcePaths';         jtype: ptArray),
    (name: 'stringImportPaths';   jtype: ptArray),
    (name: 'subConfigurations';   jtype: ptObject),
    (name: 'subPackages';         jtype: ptArray),
    (name: 'systemDependencies';  jtype: ptValue),
    (name: 'targetName';          jtype: ptValue),
    (name: 'targetPath';          jtype: ptValue),
    (name: 'targetType';          jtype: ptValue),
    (name: 'unittest';            jtype: ptArray),
    (name: 'unittest-cov';        jtype: ptArray),
    (name: 'versions';            jtype: ptArray),
    (name: 'workingDirectory';    jtype: ptValue)
  );

{$REGION TCEDubProjectPropAddPanel ---------------------------------------------}
constructor TCEDubProjectPropAddPanel.construct(event: TDubPropAddEvent; json: TJSONData);
var
  layout: TPanel;
  i: integer;
begin
  inherited create(nil);
  fJson := json;
  width := 280;
  height := 130;
  fEvent := event;
  caption := 'add a DUB property';
  Position := poMainFormCenter;
  ShowHint:=true;
  //
  fSelType := TRadioGroup.Create(self);
  fSelType.Parent := self;
  fSelType.Items.AddStrings(['array', 'object', 'value']);
  fSelType.Align:= alClient;
  fSelType.BorderSpacing.Around:=2;
  fSelType.Caption:= 'type';
  fSelType.ItemIndex:=2;
  fSelType.Hint:= 'type of the property to add';
  fSelType.OnSelectionChanged:= @selTypeChanged;
  //
  layout := TPanel.Create(self);
  layout.Parent := self;
  layout.Align := alBottom;
  layout.Height := 32;
  layout.BevelOuter:= bvNone;
  //
  fEdName := TComboBox.Create(self);
  fEdName.Parent := layout;
  fEdName.Align:=alClient;
  fEdName.BorderSpacing.Around:=4;
  fEdName.Width:=80;
  fEdName.Hint:='name of the property to add';
  for i:= low(proposals) to high(proposals) do
    fEdName.Items.Add(proposals[i].name);
  fEdName.AutoComplete := true;
  fEdName.OnChange := @setSelFromProposal;
  fEdName.OnSelect:= @setSelFromProposal;
  //
  fBtnValidate := TBitBtn.Create(self);
  fBtnValidate.Parent := layout;
  fBtnValidate.Align:=alRight;
  fBtnValidate.BorderSpacing.Around:=4;
  fBtnValidate.Width:= 26;
  fBtnValidate.OnClick:=@doValidate;
  fBtnValidate.Hint:='accept and add a property';
  AssignPng(fBtnValidate, 'ACCEPT');
  //
  selTypeChanged(nil);
end;

procedure TCEDubProjectPropAddPanel.selTypeChanged(sender: TObject);
begin
  if fJson.isNotNil then
    fEdName.Enabled := fJson.JSONType <> TJSONtype.jtArray;
end;

procedure TCEDubProjectPropAddPanel.setSelFromProposal(sender: TObject);
var
  i: integer;
begin
  fSelType.Enabled:=true;
  for i:= low(proposals) to high(proposals) do
  begin
    if fEdName.Text = proposals[i].name then
    begin
      case proposals[i].jtype of
        ptArray:fSelType.ItemIndex:=0;
        ptObject:fSelType.ItemIndex:=1;
        ptValue:fSelType.ItemIndex:=2;
      end;
      fSelType.Enabled := false;
      break;
    end;
  end;
end;

procedure TCEDubProjectPropAddPanel.doValidate(sender: TObject);
var
  tpe: TJSONtype;
begin
  if assigned(fEvent) then
  begin
    case fSelType.ItemIndex of
      0: tpe := TJSONtype.jtArray;
      1: tpe := TJSONtype.jtObject;
      else tpe := TJSONtype.jtString;
    end;
    if fEdName.Enabled and (fEdName.Text = '') then
      dlgOkError('New properties require a name')
    else
    begin
      fEvent(fEdName.Text, tpe);
      Close;
    end;
  end;
end;
{$ENDREGION}

{$REGION Standard Comp/Obj -----------------------------------------------------}
constructor TCEDubProjectEditorWidget.create(aOwner: TComponent);
begin
  inherited;
  setToolBarVisible(true);
  AssignPng(btnAcceptProp, 'ACCEPT');
end;

procedure TCEDubProjectEditorWidget.SetVisible(value: boolean);
begin
  inherited;
  if not value then
    exit;
  updateEditor;
end;

procedure TCEDubProjectEditorWidget.setToolBarFlat(value: boolean);
begin
  inherited;
  btnAcceptProp.Flat:=value;
  fltEdit.Flat:=value;
end;
{$ENDREGION}

{$REGION ICEProjectObserver ----------------------------------------------------}
procedure TCEDubProjectEditorWidget.projNew(project: ICECommonProject);
begin
  fProj := nil;
  enabled := false;
  if project.getFormat <> pfDUB then
    exit;
  enabled := true;
  fProj := TCEDubProject(project.getProject);
end;

procedure TCEDubProjectEditorWidget.projChanged(project: ICECommonProject);
begin
  if fProj.isNil then
    exit;
  if project.getProject <> fProj then
    exit;
  if not Visible then
    exit;

  updateEditor;
end;

procedure TCEDubProjectEditorWidget.projClosing(project: ICECommonProject);
begin
  if fProj.isNil then
    exit;
  if project.getProject <> fProj then
    exit;
  fProj := nil;

  updateEditor;
  enabled := false;
end;

procedure TCEDubProjectEditorWidget.projFocused(project: ICECommonProject);
begin
  fProj := nil;
  enabled := false;
  if project.getFormat <> pfDUB then
  begin
    updateEditor;
    exit;
  end;
  fProj := TCEDubProject(project.getProject);
  enabled := true;
  if not Visible then
    exit;

  if fProj.isSDL then
  begin
    edProp.Enabled:= false;
    btnAcceptProp.Enabled:=false;
  end;

  updateEditor;
end;

procedure TCEDubProjectEditorWidget.projCompiling(project: ICECommonProject);
begin
end;

procedure TCEDubProjectEditorWidget.projCompiled(project: ICECommonProject; success: boolean);
begin
end;
{$ENDREGION}

{$REGION Editor ----------------------------------------------------------------}
procedure TCEDubProjectEditorWidget.propTreeSelectionChanged(Sender: TObject);
var
  tpe: TJSONtype;
begin
  fSelectedNode := nil;
  btnDelProp.Enabled := false;
  btnAddProp.Enabled := false;
  btnCloneObject.Enabled := false;
  if propTree.Selected.isNil then
    exit;

  fSelectedNode := propTree.Selected;
  tpe := TJSONData(fSelectedNode.Data).JSONType;
  btnDelProp.Enabled := (fSelectedNode.Level > 0) and (fSelectedNode.Text <> 'name')
    and fSelectedNode.data.isNotNil;
  btnAddProp.Enabled := tpe in [jtObject, jtArray];
  btnCloneObject.Enabled := (tpe = jtObject) and (fSelectedNode.Level > 0);
  updateValueEditor;
end;

procedure TCEDubProjectEditorWidget.btnAcceptPropClick(Sender: TObject);
begin
  if fSelectedNode.isNil then
    exit;
  setJsonValueFromEditor;
  propTree.FullExpand;
end;

procedure TCEDubProjectEditorWidget.btnAddPropClick(Sender: TObject);
var
  pnl: TCEDubProjectPropAddPanel;
begin
  if fSelectedNode.isNil then
    exit;
  pnl := TCEDubProjectPropAddPanel.construct(@addProp, TJSONData(fSelectedNode.Data));
  pnl.ShowModal;
  pnl.Free;
end;

procedure TCEDubProjectEditorWidget.addProp(const propName: string;
  tpe: TJSONtype);
var
  arr: TJSONArray;
  obj: TJSONObject;
  nod: TTreeNode;
begin
  if fSelectedNode.isNil then
    exit;
  fProj.beginModification;
  if TJSONData(fSelectedNode.Data).JSONType = jtArray then
  begin
    arr := TJSONArray(fSelectedNode.Data);
    case tpe of
      jtArray: arr.Add(TJSONArray.Create());
      jtObject: arr.Add(TJSONObject.Create());
      jtString:arr.Add('<value>');
    end;
  end
  else if TJSONData(fSelectedNode.Data).JSONType = jtObject then
  begin
    obj := TJSONObject(fSelectedNode.Data);
    case tpe of
      jtArray: obj.Add(propName, TJSONArray.Create());
      jtObject: obj.Add(propName, TJSONObject.Create());
      jtString: obj.Add(propName, '<value>');
    end;
  end;
  fProj.endModification;
  propTree.FullExpand;
  nod := propTree.Items.FindNodeWithText('<value>');
  if nod.isNil then
    nod := propTree.Items.FindNodeWithText(propName);
  if nod.isNotNil then
  begin
    propTree.Selected := nod;
    propTree.MakeSelectionVisible;
  end;
end;

procedure TCEDubProjectEditorWidget.btnDelPropClick(Sender: TObject);
var
  prt: TJSONData;
  sel: TTreeNode;
begin
  if fSelectedNode.isNil then exit;
  if fSelectedNode.Level = 0 then exit;
  if fSelectedNode.Text = 'name' then exit;
  if fSelectedNode.Data.isNil then exit;
  if fSelectedNode.Parent.Data.isNil then exit;

  fProj.beginModification;
  prt := TJSONData(fSelectedNode.Parent.Data);
  if prt.JSONType = jtObject then
    TJSONObject(prt).Delete(fSelectedNode.Index)
  else if prt.JSONType = jtArray then
    TJSONArray(prt).Delete(fSelectedNode.Index);
  sel := fSelectedNode.GetPrevSibling;
  if sel.isNil then
    sel := fSelectedNode.GetNextSibling;
  if sel.isNil then
      sel := fSelectedNode.Parent;
  if sel.isNotNil then
    sel.Selected:=true;
  fProj.endModification;

  updateValueEditor;
end;

procedure TCEDubProjectEditorWidget.btnRefreshClick(Sender: TObject);
begin
  if fProj.isNil or not fProj.filename.fileExists then
      exit;
  fProj.loadFromFile(fProj.filename);
end;

procedure TCEDubProjectEditorWidget.btnCloneObjectClick(Sender: TObject);
var
  dat: TJSONData;
  prt: TJSONData;
  arr: TJSONArray;
  obj: TJSONObject;
  nme: string = '';
  inm: string;
  idx: integer = 0;
begin
  if fSelectedNode.isNil or fSelectedNode.Data.isNil or fProj.isNil or
    fSelectedNode.Parent.Data.isNil then
      exit;

  dat := TJSONData(fSelectedNode.Data);
  prt := TJSONData(fSelectedNode.Parent.Data);

  if ((prt.JSONType <> jtArray) and (prt.JSONType <> jtObject)) or
    (dat.JSONType <> jtObject) then
      exit;

  dat := dat.Clone;
  if prt.JSONType = jtArray then
  begin
    fProj.beginModification;
    arr := TJSONArray(prt);
    arr.Insert(arr.Count, dat);
    fProj.endModification;
  end
  else
  begin
    if not InputQuery('Clone object', 'name of the clone', nme) then
      exit;
    fProj.beginModification;
    obj := TJSONObject(prt);
    inm := nme;
    while obj.IndexOfName(inm) <> -1 do
    begin
      inm := format('%s_%d', [nme, idx]);
      idx += 1;
    end;
    obj.Add(inm, dat);
    fProj.endModification;
  end;
end;

procedure TCEDubProjectEditorWidget.MenuItem1Click(Sender: TObject);
begin
  if fProj.isNil or not fProj.filename.fileExists then
    exit;
  fProj.loadFromFile(fProj.filename);
end;

procedure TCEDubProjectEditorWidget.setJsonValueFromEditor;
var
  dat: TJSONData;
  vFloat: TJSONFloat;
  vInt: integer;
  vInt64: int64;
  vBool: boolean;
begin
  if fSelectedNode.isNil or fSelectedNode.Data.isNil or fProj.isNil then
    exit;

  fProj.beginModification;
  dat := TJSONData(fSelectedNode.Data);
  case dat.JSONType of
    jtNumber:
      case TJSONNumber(dat).NumberType of
        ntFloat:
          if TryStrToFloat(edProp.Text, vFloat) then
            dat.AsFloat := vFloat;
        ntInt64:
          if TryStrToInt64(edProp.Text, vInt64) then
            dat.AsInt64 := vInt64;
        ntInteger:
          if TryStrToInt(edProp.Text, vInt) then
            dat.AsInteger := vInt;
      end;
     jtBoolean:
      if TryStrToBool(edProp.Text, vBool) then
        dat.AsBoolean := vBool;
      jtString:
        dat.AsString := edProp.Text;
  end;
  fProj.endModification;
end;

procedure TCEDubProjectEditorWidget.updateValueEditor;
var
  dat: TJSONData;
begin
  edProp.Clear;
  if fSelectedNode.isNil then exit;
  if fSelectedNode.Data.isNil then exit;

  dat := TJSONData(fSelectedNode.Data);
  case dat.JSONType of
    jtNumber:
      case TJSONNumber(dat).NumberType of
        ntFloat:
          edProp.Text := FloatToStr(dat.AsFloat);
        ntInt64:
          edProp.Text := IntToStr(dat.AsInt64);
        ntInteger:
          edProp.Text := IntToStr(dat.AsInteger);
      end;
    jtBoolean:
      edProp.Text := BoolToStr(dat.AsBoolean);
    jtString:
      edProp.Text := dat.AsString;
  end;
end;

procedure TCEDubProjectEditorWidget.updateEditor;

  procedure addPropsFrom(node: TTreeNode; data: TJSONData);
  var
    i: integer;
    c: TTreeNode;
  begin
    node.Data:= data;
    if data.JSONType = jtObject then for i := 0 to data.Count-1 do
    begin
      node.ImageIndex:=7;
      node.SelectedIndex:=7;
      node.StateIndex:=7;
      c := node.TreeNodes.AddChildObject(node, TJSONObject(data).Names[i],
        TJSONObject(data).Items[i]);
      case TJSONObject(data).Items[i].JSONType of
        jtObject, jtArray:
          addPropsFrom(c, TJSONObject(data).Items[i]);
        else begin
          c.ImageIndex:=9;
          c.SelectedIndex:=9;
          c.StateIndex:=9;
        end;
      end;
    end else if data.JSONType = jtArray then for i := 0 to data.Count-1 do
    begin
      node.ImageIndex:=8;
      node.SelectedIndex:=8;
      node.StateIndex:=8;
      c := node.TreeNodes.AddChildObject(node, format('item %d',[i]),
        TJSONArray(data).Items[i]);
      case TJSONArray(data).Items[i].JSONType of
        jtObject, jtArray:
          addPropsFrom(c, TJSONArray(data).Items[i]);
        else begin
          c.ImageIndex:=9;
          c.SelectedIndex:=9;
          c.StateIndex:=9;
        end;
      end;
    end;
  end;
var
  str: string = '';
  rcl: TTreeNode;
begin

  if propTree.Selected.isNotNil then
    str := propTree.Selected.GetTextPath;

  propTree.Items.Clear;
  edProp.Clear;
  if fProj.isNil or fProj.json.isNil then
    exit;

  propTree.BeginUpdate;
  addPropsFrom(propTree.Items.Add(nil, 'project'), fProj.json);
  if str.isNotEmpty then
  begin
    rcl := propTree.Items.FindNodeWithTextPath(str);
    if rcl.isNotNil then
    begin
      rcl.Selected := true;
      rcl.MakeVisible;
    end;
  end;
  propTree.EndUpdate;
end;
{$ENDREGION}

end.

