#property strict
#property version   "0.043"
#property description "EAGOLD - BUY/SELL independent machines - Rules 1 to 6"

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
input double MiniGrid2                = 80.0;
input double SmartGrid2               = 60.0;
input double PendingStepTrail         = 50.0;
input int    MaxTrades                = 2000;
input bool   EnableCloseBy            = false;
input double BuyProgressionTolerance  = 10.0;

string EA_NAME = "EAGOLD";
bool BuyInitialCycleStarted = false;
bool SellInitialCycleStarted = false;

// ============================================================
// COMMON UTILITIES
// ============================================================

double PointsToPrice(double points){ return(points * Point); }
double NormalizePrice(double price){ return(NormalizeDouble(price, Digits)); }
double NormalizeLot(double lot){ if(lot<Lot) lot=Lot; if(MaxOpenLot>0.0 && lot>MaxOpenLot) lot=MaxOpenLot; return(NormalizeDouble(lot,DigitsLots)); }
bool IsEAGOLDOrder(){ return(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber); }

int CountOrdersByType(int type){ int count=0; for(int i=OrdersTotal()-1;i>=0;i--){ if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue; if(!IsEAGOLDOrder()) continue; if(OrderType()==type) count++; } return(count); }
int CountDirectionPositions(int direction){ return(CountOrdersByType(direction==OP_BUY?OP_BUY:OP_SELL)); }
int CountDirectionPending(int direction){ return(CountOrdersByType(direction==OP_BUY?OP_BUYSTOP:OP_SELLSTOP)); }

double DirectionBasketProfit(int direction){ int type=(direction==OP_BUY?OP_BUY:OP_SELL); double total=0.0; for(int i=OrdersTotal()-1;i>=0;i--){ if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue; if(!IsEAGOLDOrder() || OrderType()!=type) continue; total+=OrderProfit(); } return(total); }

int SendPending(int type,double price,double lots,string comment){ RefreshRates(); double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point; price=NormalizePrice(price); lots=NormalizeLot(lots); if(type==OP_BUYSTOP && price<=Ask+stopLevel) return(-1); if(type==OP_SELLSTOP && price>=Bid-stopLevel) return(-1); ResetLastError(); int ticket=OrderSend(Symbol(),type,lots,price,0,0,0,comment,MagicNumber,0,clrNONE); if(ticket<0) Print(EA_NAME," OrderSend failed. type=",type," price=",DoubleToString(price,Digits)," lot=",DoubleToString(lots,DigitsLots)," comment=",comment," error=",GetLastError()); else Print(EA_NAME," pending created. ticket=",ticket," type=",type," price=",DoubleToString(price,Digits)," lot=",DoubleToString(lots,DigitsLots)," comment=",comment); return(ticket); }

bool DeletePendingOrder(int ticket){ if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES)) return(false); if(!IsEAGOLDOrder()) return(false); int type=OrderType(); if(type!=OP_BUYSTOP && type!=OP_SELLSTOP) return(false); ResetLastError(); if(!OrderDelete(ticket)){ Print(EA_NAME," pending delete failed. ticket=",ticket," error=",GetLastError()); return(false); } return(true); }
bool CloseMarketOrder(int ticket){ if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES)) return(false); if(!IsEAGOLDOrder()) return(false); int type=OrderType(); if(type!=OP_BUY && type!=OP_SELL) return(false); RefreshRates(); double lots=OrderLots(); double price=(type==OP_BUY?Bid:Ask); ResetLastError(); if(!OrderClose(ticket,lots,NormalizePrice(price),0,clrNONE)){ Print(EA_NAME," market close failed. ticket=",ticket," type=",type," error=",GetLastError()); return(false); } return(true); }

// ============================================================
// RULE 1
// ============================================================
void BuyCreateFirstOrder(){ if(BuyInitialCycleStarted) return; if(CountDirectionPositions(OP_BUY)>0) return; if(CountDirectionPending(OP_BUY)>0) return; RefreshRates(); int ticket=SendPending(OP_BUYSTOP,NormalizePrice(Ask+PointsToPrice(MiniGrid1)),Lot,"EAGOLD FIRST BUY"); if(ticket>0) BuyInitialCycleStarted=true; }
void SellCreateFirstOrder(){ if(SellInitialCycleStarted) return; if(CountDirectionPositions(OP_SELL)>0) return; if(CountDirectionPending(OP_SELL)>0) return; RefreshRates(); int ticket=SendPending(OP_SELLSTOP,NormalizePrice(Bid-PointsToPrice(MiniGrid1)),Lot,"EAGOLD FIRST SELL"); if(ticket>0) SellInitialCycleStarted=true; }

// ============================================================
// RULE 2 + RULE 3
// ============================================================

bool GetLatestActivatedPosition(int direction,double &latestPrice,double &latestLot,int &latestTicket){ int type=(direction==OP_BUY?OP_BUY:OP_SELL); latestPrice=0.0; latestLot=NormalizeLot(Lot); latestTicket=-1; datetime latestTime=0; bool found=false; for(int i=OrdersTotal()-1;i>=0;i--){ if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue; if(!IsEAGOLDOrder() || OrderType()!=type) continue; datetime t=OrderOpenTime(); int ticket=OrderTicket(); if(!found || t>latestTime || (t==latestTime && ticket>latestTicket)){ found=true; latestTime=t; latestPrice=OrderOpenPrice(); latestLot=OrderLots(); latestTicket=ticket; } } return(found); }

// RULE 3: one common progression for BUY and SELL.
// The reference is always the most recently ACTIVATED market order,
// never a pending order. If there is no position in this direction,
// the next cycle starts from the initial Lot.
double NextRecoveryLot(double previousLot)
{
   if(previousLot <= 0.0) return(NormalizeLot(Lot));
   double next = (previousLot * Multiplier) + LotIncrement;
   return(NormalizeLot(next));
}

void BuyRecovery()
{
   if(SmartGrid1<=0.0) return;
   if(CountDirectionPositions(OP_BUY)<=0) return;
   if(CountDirectionPending(OP_BUY)>0) return;

   double lastPrice=0.0,lastLot=NormalizeLot(Lot); int lastTicket=-1;
   if(!GetLatestActivatedPosition(OP_BUY,lastPrice,lastLot,lastTicket)) return;

   RefreshRates();

   // RULE 2 BUY: price must move MORE THAN 2 x SmartGrid1 downward
   // from the LAST ACTIVATED BUY. The latest activated BUY is the
   // only reference; older BUY positions are never used.
   double trigger=lastPrice-PointsToPrice(2.0*SmartGrid1);
   if(Bid>=trigger) return;

   // Recovery BUY STOP is one SmartGrid1 above the adverse reference,
   // i.e. last activated BUY - SmartGrid1.
   double newStop=NormalizePrice(lastPrice-PointsToPrice(SmartGrid1));
   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(newStop<=Ask+stopLevel) return;

   double nextLot=NextRecoveryLot(lastLot);

   Print(EA_NAME," BUY RULE 2/3 AUTHORIZED. lastTicket=",lastTicket,
         " lastPrice=",DoubleToString(lastPrice,Digits),
         " lastLot=",DoubleToString(lastLot,DigitsLots),
         " trigger=",DoubleToString(trigger,Digits),
         " Bid=",DoubleToString(Bid,Digits),
         " newStop=",DoubleToString(newStop,Digits),
         " nextLot=",DoubleToString(nextLot,DigitsLots));

   int ticket=SendPending(OP_BUYSTOP,newStop,nextLot,"EAGOLD BUY RECOVERY");
   if(ticket<0)
      Print(EA_NAME," BUY RULE 2/3: recovery STOP was NOT created.");
}

void SellRecovery()
{
   if(SmartGrid1<=0.0) return;
   if(CountDirectionPositions(OP_SELL)<=0) return;
   if(CountDirectionPending(OP_SELL)>0) return;

   double lastPrice=0.0,lastLot=NormalizeLot(Lot); int lastTicket=-1;
   if(!GetLatestActivatedPosition(OP_SELL,lastPrice,lastLot,lastTicket)) return;

   RefreshRates();

   // RULE 2 SELL: price must move MORE THAN 2 x SmartGrid1 upward
   // from the LAST ACTIVATED SELL. The latest activated SELL is the
   // only reference; older SELL positions are never used.
   double trigger=lastPrice+PointsToPrice(2.0*SmartGrid1);
   if(Ask<=trigger) return;

   // Recovery SELL STOP is one SmartGrid1 below the adverse reference,
   // i.e. last activated SELL + SmartGrid1.
   double newStop=NormalizePrice(lastPrice+PointsToPrice(SmartGrid1));
   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(newStop>=Bid-stopLevel) return;

   double nextLot=NextRecoveryLot(lastLot);

   Print(EA_NAME," SELL RULE 2/3 AUTHORIZED. lastTicket=",lastTicket,
         " lastPrice=",DoubleToString(lastPrice,Digits),
         " lastLot=",DoubleToString(lastLot,DigitsLots),
         " trigger=",DoubleToString(trigger,Digits),
         " Ask=",DoubleToString(Ask,Digits),
         " newStop=",DoubleToString(newStop,Digits),
         " nextLot=",DoubleToString(nextLot,DigitsLots));

   int ticket=SendPending(OP_SELLSTOP,newStop,nextLot,"EAGOLD SELL RECOVERY");
   if(ticket<0)
      Print(EA_NAME," SELL RULE 2/3: recovery STOP was NOT created.");
}

// ============================================================
// RULE 6
// ============================================================
void TrailAllStopOrders(){ if(SmartGrid1<=0.0 || PendingStepTrail<=0.0) return; double trailDistance=PointsToPrice(2.0*SmartGrid1); double trailStep=PointsToPrice(PendingStepTrail); double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point; for(int i=OrdersTotal()-1;i>=0;i--){ if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue; if(!IsEAGOLDOrder()) continue; int type=OrderType(); if(type!=OP_BUYSTOP && type!=OP_SELLSTOP) continue; RefreshRates(); double current=OrderOpenPrice(),desired=current,movement=0.0; if(type==OP_SELLSTOP){ double distance=Bid-current; if(distance<=trailDistance) continue; desired=NormalizePrice(Bid-trailDistance); movement=desired-current; if(movement<trailStep || desired<=current || desired>=Bid-stopLevel) continue; } else { double distance=current-Ask; if(distance<=trailDistance) continue; desired=NormalizePrice(Ask+trailDistance); movement=current-desired; if(movement<trailStep || desired>=current || desired<=Ask+stopLevel) continue; } int ticket=OrderTicket(); ResetLastError(); if(!OrderModify(ticket,desired,0,0,0,clrNONE)) Print(EA_NAME," RULE 6: STOP TRAIL FAILED. ticket=",ticket," error=",GetLastError()); else Print(EA_NAME," RULE 6: STOP TRAIL. ticket=",ticket," from=",DoubleToString(current,Digits)," to=",DoubleToString(desired,Digits)); } }

// ============================================================
// RULE 4
// ============================================================
void BuyCreateReentryAfterSingleTP(){ RefreshRates(); SendPending(OP_BUYSTOP,NormalizePrice(Ask+PointsToPrice(MiniGrid1)),Lot,"EAGOLD BUY TP REENTRY"); }
void SellCreateReentryAfterSingleTP(){ RefreshRates(); SendPending(OP_SELLSTOP,NormalizePrice(Bid-PointsToPrice(MiniGrid1)),Lot,"EAGOLD SELL TP REENTRY"); }
void BuySingleTakeProfit(){ if(TakeProfit<=0.0 || CountDirectionPositions(OP_BUY)!=1) return; for(int i=OrdersTotal()-1;i>=0;i--){ if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue; if(!IsEAGOLDOrder() || OrderType()!=OP_BUY) continue; double profit=OrderProfit(); if(profit<TakeProfit) continue; int ticket=OrderTicket(); if(CloseMarketOrder(ticket)){ Print(EA_NAME," BUY RULE 4: TakeProfit reached. ticket=",ticket," profit=",DoubleToString(profit,2)); BuyCreateReentryAfterSingleTP(); } break; } }
void SellSingleTakeProfit(){ if(TakeProfit<=0.0 || CountDirectionPositions(OP_SELL)!=1) return; for(int i=OrdersTotal()-1;i>=0;i--){ if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue; if(!IsEAGOLDOrder() || OrderType()!=OP_SELL) continue; double profit=OrderProfit(); if(profit<TakeProfit) continue; int ticket=OrderTicket(); if(CloseMarketOrder(ticket)){ Print(EA_NAME," SELL RULE 4: TakeProfit reached. ticket=",ticket," profit=",DoubleToString(profit,2)); SellCreateReentryAfterSingleTP(); } break; } }

// ============================================================
// RULE 5
// ============================================================
bool CloseAllDirectionPending(int direction){ int type=(direction==OP_BUY?OP_BUYSTOP:OP_SELLSTOP); bool ok=true; for(int i=OrdersTotal()-1;i>=0;i--){ if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue; if(!IsEAGOLDOrder() || OrderType()!=type) continue; if(!DeletePendingOrder(OrderTicket())) ok=false; } return(ok); }
void BuyBasketClose(){ int count=CountDirectionPositions(OP_BUY); if(count<=1 || TakeProfit<=0.0) return; double target=count*TakeProfit; if(DirectionBasketProfit(OP_BUY)<target) return; Print(EA_NAME," BUY RULE 5: basket target reached. count=",count," target=",DoubleToString(target,2)); for(int i=OrdersTotal()-1;i>=0;i--){ if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue; if(!IsEAGOLDOrder() || OrderType()!=OP_BUY) continue; CloseMarketOrder(OrderTicket()); } CloseAllDirectionPending(OP_BUY); }
void SellBasketClose(){ int count=CountDirectionPositions(OP_SELL); if(count<=1 || TakeProfit<=0.0) return; double target=count*TakeProfit; if(DirectionBasketProfit(OP_SELL)<target) return; Print(EA_NAME," SELL RULE 5: basket target reached. count=",count," target=",DoubleToString(target,2)); for(int i=OrdersTotal()-1;i>=0;i--){ if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue; if(!IsEAGOLDOrder() || OrderType()!=OP_SELL) continue; CloseMarketOrder(OrderTicket()); } CloseAllDirectionPending(OP_SELL); }

void BuyMachine(){ BuyBasketClose(); BuySingleTakeProfit(); BuyRecovery(); BuyCreateFirstOrder(); }
void SellMachine(){ SellBasketClose(); SellSingleTakeProfit(); SellRecovery(); SellCreateFirstOrder(); }

int OnInit(){ Print(EA_NAME," v0.043 initialized. Rules R1-R6 active. Multiplier=",DoubleToString(Multiplier,2)," LotIncrement=",DoubleToString(LotIncrement,DigitsLots)); BuyCreateFirstOrder(); SellCreateFirstOrder(); return(INIT_SUCCEEDED); }
void OnDeinit(const int reason){}
void OnTick(){ TrailAllStopOrders(); BuyMachine(); SellMachine(); }