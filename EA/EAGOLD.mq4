#property strict
#property version   "0.069"
#property description "EAGOLD - BUY/SELL independent machines - Rules 1 to 9 + Backtest Panel"

input int    MagicNumber              = 1001;
input double Lot                      = 0.01;
input double Multiplier               = 1.10;
input int    DigitsLots               = 2;
input double LotIncrement             = 0.02;
input double MaxOpenLot               = 3.00;
input double TakeProfit               = 5.00;
input double SellProfit               = 30.00;
input double BasketLoss               = 100.00;
input int    SpreadLimit              = 100;
input int    WaitSeconds              = 0;
input double FirstStep                = 160.0;
input double MiniGrid1                = 250.0;
input double SmartGrid1               = 80.0;
input double RecoveryMinDistance      = 110.0;
input double MiniGrid2                = 80.0;
input double SmartGrid2               = 60.0;
input double PendingStepTrail         = 50.0;
input double BasketRestartStep        = 160.0;
input int    MaxTrades                = 2000;
input bool   EnableCloseBy            = true;
input double BuyProgressionTolerance  = 10.0;

string EA_NAME = "EAGOLD";

// -----------------------------------------------------------------------------
// BACKTEST PANEL - embedded in EA, upper-right corner
// -----------------------------------------------------------------------------
string PANEL_PREFIX = "EAGOLD_BT_";
double g_panelMinProfit=0.0;
double g_panelMaxLots=0.0;
bool g_panelInitialized=false;

void PanelCreateLabel(string id,int row)
{
   string name=PANEL_PREFIX+id;
   if(ObjectFind(0,name)>=0) return;
   ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,15);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,15+row*18);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}
void PanelSetLabel(string id,string text,int row)
{
   string name=PANEL_PREFIX+id;
   PanelCreateLabel(id,row);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,15);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,15+row*18);
}
void PanelDelete()
{
   string ids[19]={"TITLE","SEP1","BUY","BUYPL","BUYT","SELL","SELLPL","SELLT","SEP2","TOTAL","MIN","LOTS","MAXLOTS","NET","PEND","PBUY","PSELL","SEP3","TIME"};
   for(int i=0;i<19;i++)
   {
      string name=PANEL_PREFIX+ids[i];
      if(ObjectFind(0,name)>=0) ObjectDelete(name);
   }
}
string PanelMoney(double value){return(DoubleToString(value,2));}
string PanelLots(double value){return(DoubleToString(value,2));}
void PanelUpdate()
{
   int buyCount=0,sellCount=0,buyPending=0,sellPending=0;
   double buyLots=0.0,sellLots=0.0,buyProfit=0.0,sellProfit=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      int type=OrderType();
      if(type==OP_BUY){buyCount++;buyLots+=OrderLots();buyProfit+=OrderProfit()+OrderSwap()+OrderCommission();}
      else if(type==OP_SELL){sellCount++;sellLots+=OrderLots();sellProfit+=OrderProfit()+OrderSwap()+OrderCommission();}
      else if(type==OP_BUYSTOP) buyPending++;
      else if(type==OP_SELLSTOP) sellPending++;
   }
   int totalPending=buyPending+sellPending;
   double totalProfit=buyProfit+sellProfit;
   double totalLots=buyLots+sellLots;
   double netLots=buyLots-sellLots;
   if(!g_panelInitialized){g_panelMinProfit=totalProfit;g_panelMaxLots=totalLots;g_panelInitialized=true;}
   else{if(totalProfit<g_panelMinProfit)g_panelMinProfit=totalProfit;if(totalLots>g_panelMaxLots)g_panelMaxLots=totalLots;}
   int row=0;
   PanelSetLabel("TITLE","EAGOLD  BACKTEST",row++);
   PanelSetLabel("SEP1","------------------------------",row++);
   PanelSetLabel("BUY",StringFormat("BUY   %3d pos   %6s lot",buyCount,PanelLots(buyLots)),row++);
   PanelSetLabel("BUYPL",StringFormat("      P/L %12s",PanelMoney(buyProfit)),row++);
   PanelSetLabel("BUYT",StringFormat("      Target %9s",PanelMoney(buyCount*TakeProfit)),row++);
   PanelSetLabel("SELL",StringFormat("SELL  %3d pos   %6s lot",sellCount,PanelLots(sellLots)),row++);
   PanelSetLabel("SELLPL",StringFormat("      P/L %12s",PanelMoney(sellProfit)),row++);
   PanelSetLabel("SELLT",StringFormat("      Target %9s",PanelMoney(sellCount*TakeProfit)),row++);
   PanelSetLabel("SEP2","------------------------------",row++);
   PanelSetLabel("TOTAL",StringFormat("TOTAL P/L %14s",PanelMoney(totalProfit)),row++);
   PanelSetLabel("MIN",StringFormat("MENOR P/L %13s",PanelMoney(g_panelMinProfit)),row++);
   PanelSetLabel("LOTS",StringFormat("LOTES ATUAIS %10s",PanelLots(totalLots)),row++);
   PanelSetLabel("MAXLOTS",StringFormat("MAIOR ACUM. LOT %6s",PanelLots(g_panelMaxLots)),row++);
   PanelSetLabel("NET",StringFormat("EXPOS. LIQUIDA %7s",PanelLots(netLots)),row++);
   PanelSetLabel("PEND",StringFormat("PENDENTES       %d",totalPending),row++);
   PanelSetLabel("PBUY",StringFormat("  BUY STOP      %d",buyPending),row++);
   PanelSetLabel("PSELL",StringFormat("  SELL STOP     %d",sellPending),row++);
   PanelSetLabel("SEP3","------------------------------",row++);
   PanelSetLabel("TIME",StringFormat("Atualizado: %s",TimeToString(TimeCurrent(),TIME_SECONDS)),row++);
   ChartRedraw(0);
}

double PointsToPrice(double points){ return(points * Point); }
double NormalizePrice(double price){ return(NormalizeDouble(price, Digits)); }
double NormalizeLot(double lot){if(lot<Lot)lot=Lot;if(MaxOpenLot>0.0&&lot>MaxOpenLot)lot=MaxOpenLot;return(NormalizeDouble(lot,DigitsLots));}
bool IsEAGOLDOrder(){ return(OrderSymbol()==Symbol()&&OrderMagicNumber()==MagicNumber); }
int CountOrdersByType(int type){int count=0;for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(!IsEAGOLDOrder())continue;if(OrderType()==type)count++;}return(count);}
int CountDirectionPositions(int direction){return(CountOrdersByType(direction==OP_BUY?OP_BUY:OP_SELL));}
int CountDirectionPending(int direction){return(CountOrdersByType(direction==OP_BUY?OP_BUYSTOP:OP_SELLSTOP));}
int CountEAGOLDOrders(){int count=0;for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(IsEAGOLDOrder())count++;}return(count);}

double DirectionBasketProfit(int direction){int type=(direction==OP_BUY?OP_BUY:OP_SELL);double total=0.0;for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(!IsEAGOLDOrder()||OrderType()!=type)continue;total+=OrderProfit();}return(total);}
double TotalEAGOLDFloatingProfit(){double total=0.0;for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(!IsEAGOLDOrder())continue;int type=OrderType();if(type==OP_BUY||type==OP_SELL)total+=OrderProfit();}return(total);}

int SendPending(int type,double price,double lots,string comment){RefreshRates();double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;price=NormalizePrice(price);lots=NormalizeLot(lots);if(type==OP_BUYSTOP&&price<=Ask+stopLevel)return(-1);if(type==OP_SELLSTOP&&price>=Bid-stopLevel)return(-1);ResetLastError();int ticket=OrderSend(Symbol(),type,lots,price,0,0,0,comment,MagicNumber,0,clrNONE);if(ticket<0)Print(EA_NAME," OrderSend failed. type=",type," error=",GetLastError());else Print(EA_NAME," pending created. ticket=",ticket," type=",type," price=",DoubleToString(price,Digits)," lot=",DoubleToString(lots,DigitsLots)," comment=",comment);return(ticket);}
bool DeletePendingOrder(int ticket){if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES))return(false);if(!IsEAGOLDOrder())return(false);int type=OrderType();if(type!=OP_BUYSTOP&&type!=OP_SELLSTOP)return(false);ResetLastError();if(!OrderDelete(ticket)){Print(EA_NAME," pending delete failed. ticket=",ticket," error=",GetLastError());return(false);}return(true);}
bool CloseMarketOrder(int ticket){if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES))return(false);if(!IsEAGOLDOrder())return(false);int type=OrderType();if(type!=OP_BUY&&type!=OP_SELL)return(false);RefreshRates();double price=(type==OP_BUY?Bid:Ask);ResetLastError();if(!OrderClose(ticket,OrderLots(),NormalizePrice(price),0,clrNONE)){Print(EA_NAME," market close failed. ticket=",ticket," error=",GetLastError());return(false);}return(true);}

void CreateFirstOrdersIfFlat(){if(CountEAGOLDOrders()!=0)return;RefreshRates();int buyTicket=SendPending(OP_BUYSTOP,Ask+PointsToPrice(FirstStep),Lot,"EAGOLD R1 FIRST BUY");int sellTicket=SendPending(OP_SELLSTOP,Bid-PointsToPrice(FirstStep),Lot,"EAGOLD R1 FIRST SELL");if(buyTicket>0||sellTicket>0)Print(EA_NAME," RULE 1: initial BUY/SELL seeds created. BUY ticket=",buyTicket," SELL ticket=",sellTicket);}

bool GetLatestActivatedPosition(int direction,double &latestPrice,double &latestLot,int &latestTicket){int type=(direction==OP_BUY?OP_BUY:OP_SELL);latestPrice=0.0;latestLot=NormalizeLot(Lot);latestTicket=-1;datetime latestTime=0;bool found=false;for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(!IsEAGOLDOrder()||OrderType()!=type)continue;datetime t=OrderOpenTime();int ticket=OrderTicket();if(!found||t>latestTime||(t==latestTime&&ticket>latestTicket)){found=true;latestTime=t;latestPrice=OrderOpenPrice();latestLot=OrderLots();latestTicket=ticket;}}return(found);}
bool HasRecoveryPending(int direction){string tag=(direction==OP_BUY?"EAGOLD BUY RECOVERY":"EAGOLD SELL RECOVERY");int type=(direction==OP_BUY?OP_BUYSTOP:OP_SELLSTOP);for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(!IsEAGOLDOrder()||OrderType()!=type)continue;if(StringFind(OrderComment(),tag,0)>=0)return(true);}return(false);}
double NextRecoveryLot(double previousLot){if(previousLot<=0.0)return(NormalizeLot(Lot));return(NormalizeLot(previousLot*Multiplier+LotIncrement));}
void BuyRecovery(){if(SmartGrid1<=0.0||RecoveryMinDistance<=0.0)return;if(CountDirectionPositions(OP_BUY)<=0||HasRecoveryPending(OP_BUY))return;double lastPrice=0.0,lastLot=NormalizeLot(Lot);int lastTicket=-1;if(!GetLatestActivatedPosition(OP_BUY,lastPrice,lastLot,lastTicket))return;RefreshRates();double distance=lastPrice-Ask;double requiredDistance=PointsToPrice(2.0*SmartGrid1);if(distance<requiredDistance)return;double newStop=NormalizePrice(Ask+PointsToPrice(RecoveryMinDistance));double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;if(newStop<=Ask+stopLevel)return;SendPending(OP_BUYSTOP,newStop,NextRecoveryLot(lastLot),"EAGOLD BUY RECOVERY");}
void SellRecovery(){if(SmartGrid1<=0.0||RecoveryMinDistance<=0.0)return;if(CountDirectionPositions(OP_SELL)<=0||HasRecoveryPending(OP_SELL))return;double lastPrice=0.0,lastLot=NormalizeLot(Lot);int lastTicket=-1;if(!GetLatestActivatedPosition(OP_SELL,lastPrice,lastLot,lastTicket))return;RefreshRates();double distance=Bid-lastPrice;double requiredDistance=PointsToPrice(2.0*SmartGrid1);if(distance<requiredDistance)return;double newStop=NormalizePrice(Bid-PointsToPrice(RecoveryMinDistance));double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;if(newStop>=Bid-stopLevel)return;SendPending(OP_SELLSTOP,newStop,NextRecoveryLot(lastLot),"EAGOLD SELL RECOVERY");}

void TrailStopOrdersRule6(){if(SmartGrid1<=0.0||RecoveryMinDistance<=0.0||PendingStepTrail<=0.0)return;double triggerDistance=PointsToPrice(2.0*SmartGrid1),trailDistance=PointsToPrice(RecoveryMinDistance),trailStep=PointsToPrice(PendingStepTrail),stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(!IsEAGOLDOrder())continue;int type=OrderType();if(type!=OP_BUYSTOP&&type!=OP_SELLSTOP)continue;string comment=OrderComment();if(StringFind(comment,"EAGOLD R1 FIRST BUY",0)>=0||StringFind(comment,"EAGOLD R1 FIRST SELL",0)>=0||StringFind(comment,"EAGOLD R7 FIRST BUY",0)>=0||StringFind(comment,"EAGOLD R7 FIRST SELL",0)>=0||StringFind(comment,"EAGOLD R7 RESTART BUY",0)>=0||StringFind(comment,"EAGOLD R7 RESTART SELL",0)>=0)continue;RefreshRates();double current=OrderOpenPrice(),desired=current,movement=0.0;if(type==OP_SELLSTOP){double distance=Bid-current;if(distance<triggerDistance)continue;desired=NormalizePrice(Bid-trailDistance);movement=desired-current;if(movement<trailStep||desired<=current||desired>=Bid-stopLevel)continue;}else{double distance=current-Ask;if(distance<triggerDistance)continue;desired=NormalizePrice(Ask+trailDistance);movement=current-desired;if(movement<trailStep||desired>=current||desired<=Ask+stopLevel)continue;}int ticket=OrderTicket();ResetLastError();if(!OrderModify(ticket,desired,0,0,0,clrNONE))Print(EA_NAME," RULE 6: STOP TRAIL FAILED. ticket=",ticket," error=",GetLastError());else Print(EA_NAME," RULE 6: STOP TRAIL. ticket=",ticket," from=",DoubleToString(current,Digits)," to=",DoubleToString(desired,Digits));}}
void TrailSpecialFirstStopOrders(){if(FirstStep<=0.0||PendingStepTrail<=0.0)return;double trailDistance=PointsToPrice(FirstStep),trailStep=PointsToPrice(PendingStepTrail),activationDistance=trailDistance+trailStep,stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(!IsEAGOLDOrder())continue;int type=OrderType();if(type!=OP_BUYSTOP&&type!=OP_SELLSTOP)continue;string comment=OrderComment();bool special=false;if(StringFind(comment,"EAGOLD R1 FIRST BUY",0)>=0)special=true;if(StringFind(comment,"EAGOLD R1 FIRST SELL",0)>=0)special=true;if(StringFind(comment,"EAGOLD R7 FIRST BUY",0)>=0)special=true;if(StringFind(comment,"EAGOLD R7 FIRST SELL",0)>=0)special=true;if(StringFind(comment,"EAGOLD R7 RESTART BUY",0)>=0)special=true;if(StringFind(comment,"EAGOLD R7 RESTART SELL",0)>=0)special=true;if(!special)continue;RefreshRates();double current=OrderOpenPrice(),desired=current,movement=0.0;if(type==OP_SELLSTOP){double distance=Bid-current;if(distance<activationDistance)continue;desired=NormalizePrice(Bid-trailDistance);movement=desired-current;if(movement<trailStep||desired<=current||desired>=Bid-stopLevel)continue;}else{double distance=current-Ask;if(distance<activationDistance)continue;desired=NormalizePrice(Ask+trailDistance);movement=current-desired;if(movement<trailStep||desired>=current||desired<=Ask+stopLevel)continue;}int ticket=OrderTicket();ResetLastError();if(!OrderModify(ticket,desired,0,0,0,clrNONE))Print(EA_NAME," RULE 7: SPECIAL STOP TRAIL FAILED. ticket=",ticket," error=",GetLastError());else Print(EA_NAME," RULE 7: SPECIAL STOP TRAIL. ticket=",ticket," from=",DoubleToString(current,Digits)," to=",DoubleToString(desired,Digits));}}

void BuyCreateReentryAfterSingleTP(){RefreshRates();SendPending(OP_BUYSTOP,Ask+PointsToPrice(MiniGrid1),Lot,"EAGOLD BUY TP REENTRY");}
void SellCreateReentryAfterSingleTP(){RefreshRates();SendPending(OP_SELLSTOP,Bid-PointsToPrice(MiniGrid1),Lot,"EAGOLD SELL TP REENTRY");}
void BuySingleTakeProfit(){if(CountDirectionPositions(OP_BUY)!=1)return;for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(!IsEAGOLDOrder()||OrderType()!=OP_BUY)continue;if(OrderProfit()<TakeProfit)continue;int ticket=OrderTicket();if(CloseMarketOrder(ticket))BuyCreateReentryAfterSingleTP();return;}}
void SellSingleTakeProfit(){if(CountDirectionPositions(OP_SELL)!=1)return;for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(!IsEAGOLDOrder()||OrderType()!=OP_SELL)continue;if(OrderProfit()<TakeProfit)continue;int ticket=OrderTicket();if(CloseMarketOrder(ticket))SellCreateReentryAfterSingleTP();return;}}
void CloseAllDirectionPending(int direction){int type=(direction==OP_BUY?OP_BUYSTOP:OP_SELLSTOP);for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(!IsEAGOLDOrder()||OrderType()!=type)continue;DeletePendingOrder(OrderTicket());}}
bool HedgeGateAllowsBasketClose(){return(TotalEAGOLDFloatingProfit()>=0.0);}
bool BuyBasketClose(){int count=CountDirectionPositions(OP_BUY);if(count<=1)return(false);double target=count*TakeProfit;if(DirectionBasketProfit(OP_BUY)<target||!HedgeGateAllowsBasketClose())return(false);for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(!IsEAGOLDOrder()||OrderType()!=OP_BUY)continue;CloseMarketOrder(OrderTicket());}if(CountDirectionPositions(OP_BUY)>0)return(false);CloseAllDirectionPending(OP_BUY);return(true);}
bool SellBasketClose(){int count=CountDirectionPositions(OP_SELL);if(count<=1)return(false);double target=count*TakeProfit;if(DirectionBasketProfit(OP_SELL)<target||!HedgeGateAllowsBasketClose())return(false);for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(!IsEAGOLDOrder()||OrderType()!=OP_SELL)continue;CloseMarketOrder(OrderTicket());}if(CountDirectionPositions(OP_SELL)>0)return(false);CloseAllDirectionPending(OP_SELL);return(true);}
void RestartEmptyBasket(int direction){if(BasketRestartStep<=0.0)return;if(CountDirectionPositions(direction)!=0)return;if(CountDirectionPending(direction)!=0)return;RefreshRates();if(direction==OP_BUY){double price=NormalizePrice(Ask+PointsToPrice(BasketRestartStep));Print(EA_NAME," RULE 8: BUY basket closed and empty. Creating R7 special BUY STOP at ",DoubleToString(price,Digits));SendPending(OP_BUYSTOP,price,Lot,"EAGOLD R7 RESTART BUY");}else{double price=NormalizePrice(Bid-PointsToPrice(BasketRestartStep));Print(EA_NAME," RULE 8: SELL basket closed and empty. Creating R7 special SELL STOP at ",DoubleToString(price,Digits));SendPending(OP_SELLSTOP,price,Lot,"EAGOLD R7 RESTART SELL");}}
bool GetLargestMarketTicket(int direction,int &ticket,double &lots){int type=(direction==OP_BUY?OP_BUY:OP_SELL);ticket=-1;lots=0.0;bool found=false;for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(!IsEAGOLDOrder()||OrderType()!=type)continue;double currentLots=OrderLots();int currentTicket=OrderTicket();if(!found||currentLots>lots||(MathAbs(currentLots-lots)<0.0000001&&currentTicket>ticket)){found=true;lots=currentLots;ticket=currentTicket;}}return(found);}
bool R9BasketTrigger(){int buyCount=CountDirectionPositions(OP_BUY),sellCount=CountDirectionPositions(OP_SELL);if(buyCount<=0||sellCount<=0)return(false);double buyTarget=buyCount*TakeProfit,sellTarget=sellCount*TakeProfit;double buyProfit=DirectionBasketProfit(OP_BUY),sellProfit=DirectionBasketProfit(OP_SELL);return(buyProfit>=buyTarget||sellProfit>=sellTarget);}
bool Rule9MultipleCloseBy(){if(!EnableCloseBy||!R9BasketTrigger())return(false);Print(EA_NAME," RULE 9: MULTIPLE CLOSEBY LIQUIDATION START. BUY=",CountDirectionPositions(OP_BUY)," SELL=",CountDirectionPositions(OP_SELL));CloseAllDirectionPending(OP_BUY);CloseAllDirectionPending(OP_SELL);int safety=0;while(CountDirectionPositions(OP_BUY)>0&&CountDirectionPositions(OP_SELL)>0&&safety<MaxTrades){int buyTicket=-1,sellTicket=-1;double buyLots=0.0,sellLots=0.0;if(!GetLargestMarketTicket(OP_BUY,buyTicket,buyLots))break;if(!GetLargestMarketTicket(OP_SELL,sellTicket,sellLots))break;ResetLastError();if(!OrderCloseBy(buyTicket,sellTicket,clrNONE)){Print(EA_NAME," RULE 9: CLOSEBY FAILED. error=",GetLastError());break;}Print(EA_NAME," RULE 9: CLOSEBY. BUY ticket=",buyTicket," lot=",DoubleToString(buyLots,DigitsLots)," SELL ticket=",sellTicket," lot=",DoubleToString(sellLots,DigitsLots));safety++;}for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(!IsEAGOLDOrder())continue;int type=OrderType();if(type==OP_BUY||type==OP_SELL)CloseMarketOrder(OrderTicket());}bool flat=(CountDirectionPositions(OP_BUY)==0&&CountDirectionPositions(OP_SELL)==0);if(flat){Print(EA_NAME," RULE 9: MULTIPLE CLOSEBY LIQUIDATION COMPLETE. MARKET FLAT.");return(true);}return(false);}
void BuyMachine(){bool r9=Rule9MultipleCloseBy();if(r9){RestartEmptyBasket(OP_BUY);RestartEmptyBasket(OP_SELL);return;}bool basketClosed=BuyBasketClose();if(basketClosed)RestartEmptyBasket(OP_BUY);BuySingleTakeProfit();BuyRecovery();}
void SellMachine(){bool basketClosed=SellBasketClose();if(basketClosed)RestartEmptyBasket(OP_SELL);SellSingleTakeProfit();SellRecovery();}

int OnInit(){g_panelInitialized=false;g_panelMinProfit=0.0;g_panelMaxLots=0.0;Print(EA_NAME," v0.069 initialized. R6=ordinary STOPs; R7=special first/restart STOPs; R8=basket restart; R9=multiple CloseBy liquidation; backtest panel=upper-right.");CreateFirstOrdersIfFlat();PanelUpdate();return(INIT_SUCCEEDED);}
void OnDeinit(const int reason){PanelDelete();}
void OnTick(){BuyMachine();SellMachine();CreateFirstOrdersIfFlat();TrailStopOrdersRule6();TrailSpecialFirstStopOrders();PanelUpdate();}
