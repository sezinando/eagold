#property strict
#property version   "0.072"
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

// R9 - Balanceamento cruzado por nova ordem pendente.
// A cesta existente permanece aberta; o R9 somente arma a perna oposta.
input bool   EnableR9Containment      = true;

string EA_NAME = "EAGOLD";

string PANEL_PREFIX = "EAGOLD_BT_";
double g_panelMinProfit=0.0;
double g_panelMaxLots=0.0;
bool g_panelInitialized=false;

// R9 state: cada ticket de mercado e processado uma unica vez.
int g_r9ProcessedTickets[];

void PanelCreate()
{
   string bg=PANEL_PREFIX+"BG";
   if(ObjectFind(0,bg)<0)
   {
      ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
      ObjectSetInteger(0,bg,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,8);
      ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,8);
      ObjectSetInteger(0,bg,OBJPROP_XSIZE,225);
      ObjectSetInteger(0,bg,OBJPROP_YSIZE,335);
      ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,clrBlack);
      ObjectSetInteger(0,bg,OBJPROP_COLOR,clrDimGray);
      ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,bg,OBJPROP_SELECTED,false);
      ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   }
}

void PanelCreateLabel(string id,int row,color clr)
{
   string name=PANEL_PREFIX+id;
   if(ObjectFind(0,name)>=0) return;
   ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,18);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,18+row*17);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
}

void PanelSet(string id,string text,int row,color clr)
{
   string name=PANEL_PREFIX+id;
   PanelCreateLabel(id,row,clr);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,18);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,18+row*17);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
}

void PanelDelete()
{
   string ids[]={"BG","TITLE","SEP1","BUY","BUYPL","BUYT","SELL","SELLPL","SELLT","SEP2","TOTAL","MIN","LOTS","MAXLOTS","NET","PEND","PBUY","PSELL","SEP3","TIME"};
   int n=ArraySize(ids);
   for(int i=0;i<n;i++)
   {
      string name=PANEL_PREFIX+ids[i];
      if(ObjectFind(0,name)>=0) ObjectDelete(name);
   }
}

string PanelMoney(double value){return(DoubleToString(value,2));}
string PanelLots(double value){return(DoubleToString(value,2));}

void PanelUpdate()
{
   PanelCreate();
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
   PanelSet("TITLE","EAGOLD  v0.072",row++,clrWhite);
   PanelSet("SEP1","==============================",row++,clrSilver);
   PanelSet("BUY",StringFormat("BUY   %3d pos   %6s lot",buyCount,PanelLots(buyLots)),row++,clrLime);
   PanelSet("BUYPL",StringFormat("P/L       %12s",PanelMoney(buyProfit)),row++,clrLime);
   PanelSet("BUYT",StringFormat("Target    %12s",PanelMoney(buyCount*TakeProfit)),row++,clrSilver);
   PanelSet("SELL",StringFormat("SELL  %3d pos   %6s lot",sellCount,PanelLots(sellLots)),row++,clrTomato);
   PanelSet("SELLPL",StringFormat("P/L       %12s",PanelMoney(sellProfit)),row++,clrTomato);
   PanelSet("SELLT",StringFormat("Target    %12s",PanelMoney(sellCount*TakeProfit)),row++,clrSilver);
   PanelSet("SEP2","==============================",row++,clrSilver);
   PanelSet("TOTAL",StringFormat("TOTAL P/L %12s",PanelMoney(totalProfit)),row++,clrWhite);
   PanelSet("MIN",StringFormat("MENOR P/L %11s",PanelMoney(g_panelMinProfit)),row++,clrYellow);
   PanelSet("LOTS",StringFormat("LOTES ATUAIS %9s",PanelLots(totalLots)),row++,clrWhite);
   PanelSet("MAXLOTS",StringFormat("MAIOR ACUM. %9s",PanelLots(g_panelMaxLots)),row++,clrYellow);
   PanelSet("NET",StringFormat("EXPOS. LIQ. %10s",PanelLots(netLots)),row++,clrWhite);
   PanelSet("PEND",StringFormat("PENDENTES     %6d",totalPending),row++,clrSilver);
   PanelSet("PBUY",StringFormat("BUY STOP      %6d",buyPending),row++,clrSilver);
   PanelSet("PSELL",StringFormat("SELL STOP     %6d",sellPending),row++,clrSilver);
   PanelSet("SEP3","==============================",row++,clrSilver);
   PanelSet("TIME",TimeToString(TimeCurrent(),TIME_SECONDS),row++,clrSilver);
   ChartRedraw(0);
}

double PointsToPrice(double points){ return(points * Point); }
double NormalizePrice(double price){ return(NormalizeDouble(price, Digits)); }
double NormalizeLot(double lot){if(lot<Lot)lot=Lot;if(MaxOpenLot>0.0&&lot>MaxOpenLot)lot=MaxOpenLot;return(NormalizeDouble(lot,DigitsLots));}
bool IsEAGOLDOrder(){ return(OrderSymbol()==Symbol()&&OrderMagicNumber()==MagicNumber); }
int CountOrdersByType(int type){int count=0;for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(!IsEAGOLDOrder())continue;if(OrderType()==type)count++;}return(count);}
int CountDirectionPositions(int direction){return(CountOrdersByType(direction==OP_BUY?OP_BUY:OP_SELL));}
int CountDirectionPending(int direction){return(CountOrdersByType(direction==OP_BUY?OP_BUYSTOP:OP_SELLSTOP);}
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

// ------------------------------------------------------------------
// R9 - BALANCEAMENTO CRUZADO
// ------------------------------------------------------------------
// Progressao observada nos logs ZEUS para as sequencias regulares:
// 0.01, 0.03, 0.05, 0.07, 0.09, 0.12, 0.14, 0.16, 0.18, 0.20,
// 0.23, 0.25, 0.27, 0.29, 0.32, 0.34, 0.37, 0.39 ...
// Formula equivalente: round(0.01 * 1.10^n + 0.02*n, 2).
double ZeusProgressionLotByIndex(int n)
{
   if(n<0) n=0;
   return(NormalizeLot(0.01*MathPow(1.10,n)+0.02*n));
}

bool LotMatchesZeusProgression(double lot,int index)
{
   double expected=ZeusProgressionLotByIndex(index);
   return(MathAbs(lot-expected)<=0.000001);
}

int HighestZeusProgressionIndex(int direction)
{
   int best=-1;
   int marketType=(direction==OP_BUY?OP_BUY:OP_SELL);
   int pendingType=(direction==OP_BUY?OP_BUYSTOP:OP_SELLSTOP);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      int type=OrderType();
      if(type!=marketType && type!=pendingType) continue;
      double lot=OrderLots();
      for(int n=0;n<100;n++)
      {
         double expected=ZeusProgressionLotByIndex(n);
         if(expected>MaxOpenLot && MaxOpenLot>0.0) break;
         if(LotMatchesZeusProgression(lot,n) && n>best) best=n;
      }
   }
   return(best);
}

double NextZeusProgressionLot(int direction)
{
   int idx=HighestZeusProgressionIndex(direction)+1;
   return(ZeusProgressionLotByIndex(idx));
}

bool R9TicketProcessed(int ticket)
{
   int n=ArraySize(g_r9ProcessedTickets);
   for(int i=0;i<n;i++) if(g_r9ProcessedTickets[i]==ticket) return(true);
   return(false);
}

void R9MarkTicketProcessed(int ticket)
{
   if(ticket<0 || R9TicketProcessed(ticket)) return;
   int n=ArraySize(g_r9ProcessedTickets);
   ArrayResize(g_r9ProcessedTickets,n+1);
   g_r9ProcessedTickets[n]=ticket;
}

bool HasR9BalanceForSource(int sourceTicket,int oppositeType)
{
   string sourceTag=StringFormat("FROM #%d",sourceTicket);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(OrderType()!=oppositeType) continue;
      if(StringFind(OrderComment(),"EAGOLD R9 BALANCE",0)<0) continue;
      if(StringFind(OrderComment(),sourceTag,0)>=0) return(true);
   }
   return(false);
}

bool R9CreateBalanceForPosition(int sourceTicket,int sourceDirection,double sourceLot)
{
   if(!EnableR9Containment) return(false);
   if(sourceTicket<0) return(false);

   int oppositeDirection=(sourceDirection==OP_BUY?OP_SELL:OP_BUY);
   int oppositePending=(oppositeDirection==OP_BUY?OP_BUYSTOP:OP_SELLSTOP);

   if(HasR9BalanceForSource(sourceTicket,oppositePending))
   {
      R9MarkTicketProcessed(sourceTicket);
      return(false);
   }

   RefreshRates();
   double distance=PointsToPrice(SmartGrid2);
   double price=0.0;
   if(oppositeDirection==OP_SELL) price=NormalizePrice(Bid-distance);
   else price=NormalizePrice(Ask+distance);

   double lots=NextZeusProgressionLot(oppositeDirection);
   if(lots<=0.0) return(false);

   string comment=StringFormat("EAGOLD R9 BALANCE FROM #%d",sourceTicket);
   int ticket=SendPending(oppositePending,price,lots,comment);
   if(ticket>0)
   {
      Print(EA_NAME," RULE 9: CROSS-BALANCE. source=",sourceTicket,
            " dir=",(sourceDirection==OP_BUY?"BUY":"SELL"),
            " sourceLot=",DoubleToString(sourceLot,DigitsLots),
            " -> pending=",ticket,
            " dir=",(oppositeDirection==OP_BUY?"BUY STOP":"SELL STOP"),
            " lot=",DoubleToString(lots,DigitsLots),
            " price=",DoubleToString(price,Digits));
      R9MarkTicketProcessed(sourceTicket);
      return(true);
   }
   return(false);
}

void Rule9CrossBalance()
{
   if(!EnableR9Containment) return;

   // Processa toda posicao de mercado ainda nao observada. Isso evita
   // depender apenas da "ultima" posicao e preserva eventos simultaneos.
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;
      int ticket=OrderTicket();
      if(R9TicketProcessed(ticket)) continue;
      double lot=OrderLots();
      R9CreateBalanceForPosition(ticket,type,lot);
   }
}

void BuyMachine(){Rule9CrossBalance();bool basketClosed=BuyBasketClose();if(basketClosed)RestartEmptyBasket(OP_BUY);BuySingleTakeProfit();BuyRecovery();}
void SellMachine(){bool basketClosed=SellBasketClose();if(basketClosed)RestartEmptyBasket(OP_SELL);SellSingleTakeProfit();SellRecovery();}

int OnInit(){ArrayResize(g_r9ProcessedTickets,0);g_panelInitialized=false;g_panelMinProfit=0.0;g_panelMaxLots=0.0;PanelUpdate();Print(EA_NAME," v0.072 initialized. R6=ordinary STOPs; R7=special first/restart STOPs; R8=basket restart; R9=cross-balance pending; panel=upper-right.");CreateFirstOrdersIfFlat();PanelUpdate();return(INIT_SUCCEEDED);}
void OnDeinit(const int reason){PanelDelete();}
void OnTick(){BuyMachine();SellMachine();CreateFirstOrdersIfFlat();TrailStopOrdersRule6();TrailSpecialFirstStopOrders();PanelUpdate();}
