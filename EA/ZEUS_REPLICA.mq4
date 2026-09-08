//+------------------------------------------------------------------+
//| ZEUS_REPLICA.mq4                                                 |
//| ZEUS Replica - controlled reverse engineering                    |
//|                                                                  |
//| V0.2                                                             |
//|                                                                  |
//| Scope                                                             |
//|   - proven bootstrap                                             |
//|   - basket reconciliation                                       |
//|   - pending activation detection                                 |
//|   - independent BUY / SELL ladder                               |
//|   - FirstStep / MinDistance / Step fallback                     |
//|   - empirical lot engine                                         |
//|                                                                  |
//| NOT IMPLEMENTED YET                                               |
//|   - StopProfit                                                    |
//|   - CloseBuySell                                                  |
//|   - Global CloseAll / MaxLoss                                     |
//|   - CloseBy orchestration                                         |
//|   - trailing                                                      |
//+------------------------------------------------------------------+
#property strict
#property version   "0.2"
#property description "ZEUS Replica V0.2 - reconciliation, activation and first ladder"

input int      Magic               = 1001;
input double   lot                 = 0.01;
input double   K_Lot               = 1.20;
input int      DigitsLot           = 2;
input double   PlusLot             = 0.01;
input double   Maxlot              = 0.62;
input int      MaxSpread           = 100;
input int      FirstStep           = 160;
input int      MinDistance         = 340;
input int      Step                = 80;
input bool     EnableLadderEntries = true;
input bool     EnableTelemetry     = true;

string PREFIX="ZEUS_REPLICA";
bool   g_first_tick=false;
int    g_last_buy_count=-1;
int    g_last_sell_count=-1;

struct SideState
{
   int market_count;
   int pending_count;
   double market_lots;
   double pending_lots;
   double lowest;
   double highest;
};

void Log(string text)
{
   if(EnableTelemetry) Print(PREFIX," | ",text);
}

string SideName(int side)
{
   return(side==OP_BUY ? "BUY" : "SELL");
}

bool IsOurOrder()
{
   return(OrderSymbol()==Symbol() && OrderMagicNumber()==Magic);
}

void GetSideState(int side,SideState &s)
{
   s.market_count=0;
   s.pending_count=0;
   s.market_lots=0.0;
   s.pending_lots=0.0;
   s.lowest=DBL_MAX;
   s.highest=-DBL_MAX;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsOurOrder()) continue;

      int type=OrderType();
      bool market=(type==OP_BUY || type==OP_SELL);
      bool same_side=(side==OP_BUY ?
                      (type==OP_BUY || type==OP_BUYSTOP || type==OP_BUYLIMIT) :
                      (type==OP_SELL || type==OP_SELLSTOP || type==OP_SELLLIMIT));
      if(!same_side) continue;

      double price=OrderOpenPrice();
      if(price<s.lowest)  s.lowest=price;
      if(price>s.highest) s.highest=price;

      if(market)
      {
         s.market_count++;
         s.market_lots+=OrderLots();
      }
      else
      {
         s.pending_count++;
         s.pending_lots+=OrderLots();
      }
   }

   if(s.lowest==DBL_MAX) s.lowest=0.0;
   if(s.highest==-DBL_MAX) s.highest=0.0;
}

double NormalizeLots(double value)
{
   double broker_min=MarketInfo(Symbol(),MODE_MINLOT);
   double broker_max=MarketInfo(Symbol(),MODE_MAXLOT);
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   double cap=MathMin(Maxlot,broker_max);

   value=MathMin(value,cap);
   value=MathMax(value,broker_min);

   if(step>0.0)
      value=MathFloor(value/step+1e-8)*step;

   value=MathMax(value,broker_min);
   return NormalizeDouble(value,DigitsLot);
}

double ZeusLot(int n)
{
   return NormalizeLots(lot*MathPow(K_Lot,n)+n*PlusLot);
}

bool ContextOK()
{
   RefreshRates();

   double spread=(Ask-Bid)/Point;
   if(spread>MaxSpread)
   {
      Log("CONTEXT REJECT | spread="+DoubleToString(spread,1)+
          " MaxSpread="+IntegerToString(MaxSpread));
      return false;
   }

   if(MarketInfo(Symbol(),MODE_TRADEALLOWED)==0)
   {
      Log("CONTEXT REJECT | symbol trade disabled");
      return false;
   }

   // IsTradeAllowed() is deliberately not used as an absolute blocker
   // in the Strategy Tester. V0.1 proved OrderSend works in this context.
   if(!IsTesting() && !IsTradeAllowed())
   {
      Log("CONTEXT REJECT | trade not allowed");
      return false;
   }

   return true;
}

bool HasPending(int type)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsOurOrder()) continue;
      if(OrderType()==type) return true;
   }
   return false;
}

bool BrokerDistanceOK(int type,double price)
{
   RefreshRates();
   double stop_level=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;

   if(type==OP_BUYSTOP && price<=Ask+stop_level)
   {
      Log("SEND REJECT | BUY STOP broker distance | price="+
          DoubleToString(price,Digits)+" ask="+DoubleToString(Ask,Digits));
      return false;
   }

   if(type==OP_SELLSTOP && price>=Bid-stop_level)
   {
      Log("SEND REJECT | SELL STOP broker distance | price="+
          DoubleToString(price,Digits)+" bid="+DoubleToString(Bid,Digits));
      return false;
   }

   return true;
}

int SendPending(int type,double price,double lots,string reason)
{
   RefreshRates();
   price=NormalizeDouble(price,Digits);
   lots=NormalizeLots(lots);

   if(!BrokerDistanceOK(type,price)) return -1;

   string side=(type==OP_BUYSTOP ? "BUY" : "SELL");
   Log("SEND ATTEMPT | side="+side+
       " reason="+reason+
       " price="+DoubleToString(price,Digits)+
       " lots="+DoubleToString(lots,DigitsLot));

   ResetLastError();
   int ticket=OrderSend(Symbol(),type,lots,price,0,0,0,
                        "ZEUS_REPLICA",Magic,0,clrNONE);
   int error=GetLastError();

   if(ticket<0)
   {
      Log("SEND ERROR | side="+side+
          " error="+IntegerToString(error)+
          " price="+DoubleToString(price,Digits)+
          " lots="+DoubleToString(lots,DigitsLot));
      return -1;
   }

   Log("SEND SUCCESS | side="+side+
       " ticket="+IntegerToString(ticket)+
       " price="+DoubleToString(price,Digits)+
       " lots="+DoubleToString(lots,DigitsLot)+
       " reason="+reason);

   return ticket;
}

void LogState(string event_name,SideState &b,SideState &s)
{
   Log(event_name+
       " | BUY market="+IntegerToString(b.market_count)+
       " pending="+IntegerToString(b.pending_count)+
       " lots="+DoubleToString(b.market_lots,DigitsLot)+
       " | SELL market="+IntegerToString(s.market_count)+
       " pending="+IntegerToString(s.pending_count)+
       " lots="+DoubleToString(s.market_lots,DigitsLot));
}

void Reconcile()
{
   SideState buy,sell;
   GetSideState(OP_BUY,buy);
   GetSideState(OP_SELL,sell);

   if(g_last_buy_count<0 || buy.market_count!=g_last_buy_count)
   {
      LogState("RECONCILE BUY COUNT CHANGE",buy,sell);
      g_last_buy_count=buy.market_count;
   }

   if(g_last_sell_count<0 || sell.market_count!=g_last_sell_count)
   {
      LogState("RECONCILE SELL COUNT CHANGE",buy,sell);
      g_last_sell_count=sell.market_count;
   }
}

void EnsureInitialOrders()
{
   if(!ContextOK()) return;

   SideState buy,sell;
   GetSideState(OP_BUY,buy);
   GetSideState(OP_SELL,sell);

   if(buy.market_count==0 && buy.pending_count==0)
   {
      RefreshRates();
      double price=NormalizeDouble(Ask+FirstStep*Point,Digits);
      SendPending(OP_BUYSTOP,price,ZeusLot(0),"INITIAL_FIRSTSTEP");
   }

   if(sell.market_count==0 && sell.pending_count==0)
   {
      RefreshRates();
      double price=NormalizeDouble(Bid-FirstStep*Point,Digits);
      SendPending(OP_SELLSTOP,price,ZeusLot(0),"INITIAL_FIRSTSTEP");
   }
}

double BuyCandidate(int count,SideState &s)
{
   RefreshRates();
   double candidate=(count==0 ? Ask+FirstStep*Point : Ask+MinDistance*Point);

   // Empirically observed Step fallback.
   if(count>0 && s.lowest>0.0 && candidate<s.lowest-Step*Point)
      candidate=Ask+Step*Point;

   return NormalizeDouble(candidate,Digits);
}

double SellCandidate(int count,SideState &s)
{
   RefreshRates();
   double candidate=(count==0 ? Bid-FirstStep*Point : Bid-MinDistance*Point);

   // Empirically observed Step fallback.
   if(count>0 && s.highest>0.0 && candidate<s.highest+Step*Point)
      candidate=Bid-Step*Point;

   return NormalizeDouble(candidate,Digits);
}

void EvaluateBuy()
{
   if(!EnableLadderEntries || !ContextOK()) return;

   SideState s;
   GetSideState(OP_BUY,s);

   // No market BUY means the initial BUY STOP is the only entry intent.
   if(s.market_count<=0) return;

   // One BUY STOP is enough until it is activated/reconciled.
   if(HasPending(OP_BUYSTOP)) return;

   int n=s.market_count;
   double price=BuyCandidate(n,s);
   double lots=ZeusLot(n);

   SendPending(OP_BUYSTOP,price,lots,"LADDER_BUY");
}

void EvaluateSell()
{
   if(!EnableLadderEntries || !ContextOK()) return;

   SideState s;
   GetSideState(OP_SELL,s);

   if(s.market_count<=0) return;
   if(HasPending(OP_SELLSTOP)) return;

   int n=s.market_count;
   double price=SellCandidate(n,s);
   double lots=ZeusLot(n);

   SendPending(OP_SELLSTOP,price,lots,"LADDER_SELL");
}

void Cycle()
{
   RefreshRates();

   Reconcile();

   // EXIT is intentionally absent in V0.2.
   // BUY and SELL engines remain independent.
   EnsureInitialOrders();
   EvaluateBuy();
   EvaluateSell();
}

int OnInit()
{
   Log("============================================================");
   Log("INIT | ZEUS_REPLICA V0.2");
   Log("INIT | Symbol="+Symbol()+" Magic="+IntegerToString(Magic));
   Log("INIT | testing="+(IsTesting()?"true":"false")+
       " digits="+IntegerToString(Digits)+
       " point="+DoubleToString(Point,Digits));
   Log("INIT | FirstStep="+IntegerToString(FirstStep)+
       " MinDistance="+IntegerToString(MinDistance)+
       " Step="+IntegerToString(Step));
   Log("INIT | stop_level="+DoubleToString(MarketInfo(Symbol(),MODE_STOPLEVEL),0)+
       " min_lot="+DoubleToString(MarketInfo(Symbol(),MODE_MINLOT),2)+
       " lot_step="+DoubleToString(MarketInfo(Symbol(),MODE_LOTSTEP),2));
   Log("INIT | returning INIT_SUCCEEDED");
   Log("============================================================");

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Log("DEINIT | reason="+IntegerToString(reason));
}

void OnTick()
{
   RefreshRates();

   if(!g_first_tick)
   {
      g_first_tick=true;
      Log("FIRST TICK | time="+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+
          " bid="+DoubleToString(Bid,Digits)+
          " ask="+DoubleToString(Ask,Digits));
   }

   Cycle();
}

//+------------------------------------------------------------------+
