//+------------------------------------------------------------------+
//| ZEUS_REPLICA_V0_2.mq4                                           |
//| Reverse-engineered MT4 replica - execution diagnostic build    |
//+------------------------------------------------------------------+
#property strict
#property version   "0.2"
#property description "ZEUS reverse-engineering replica V0.2 - initial orders + ladder + trailing + diagnostics"

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
input int      StepTrallOrders     = 50;
input bool     EnableLadderEntries = true;
input bool     EnableTrailing      = true;
input bool     EnableTelemetry     = true;
input bool     BypassTradeContextInTester = true;
input int      TimerSeconds        = 1;

string PREFIX="ZEUS_REPLICA";
datetime last_cycle=0;

struct SideState
{
   int market_count;
   int pending_count;
   double market_lots;
   double pending_lots;
   double lowest;
   double highest;
};

void Log(string msg)
{
   Print(PREFIX," | ",msg);
}

void Decision(string stage,string side,string action,string reason,double price,double lots,int count)
{
   if(!EnableTelemetry) return;
   Print(PREFIX,"|DECISION|",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
         "|stage=",stage,"|side=",side,"|action=",action,"|reason=",reason,
         "|price=",DoubleToString(price,Digits),"|lots=",DoubleToString(lots,DigitsLot),"|count=",count,
         "|bid=",DoubleToString(Bid,Digits),"|ask=",DoubleToString(Ask,Digits));
}

bool IsMine()
{
   return(OrderSymbol()==Symbol() && OrderMagicNumber()==Magic);
}

void State(int side,SideState &s)
{
   s.market_count=0; s.pending_count=0; s.market_lots=0; s.pending_lots=0;
   s.lowest=DBL_MAX; s.highest=-DBL_MAX;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsMine()) continue;
      int t=OrderType();
      bool market=(t==OP_BUY || t==OP_SELL);
      bool side_ok=(side==OP_BUY ? (t==OP_BUY || t==OP_BUYSTOP || t==OP_BUYLIMIT)
                                 : (t==OP_SELL || t==OP_SELLSTOP || t==OP_SELLLIMIT));
      if(!side_ok) continue;
      double p=OrderOpenPrice();
      if(p<s.lowest) s.lowest=p;
      if(p>s.highest) s.highest=p;
      if(market){s.market_count++;s.market_lots+=OrderLots();}
      else{s.pending_count++;s.pending_lots+=OrderLots();}
   }
   if(s.lowest==DBL_MAX) s.lowest=0;
   if(s.highest==-DBL_MAX) s.highest=0;
}

double NormalizeLot(double value)
{
   double broker_min=MarketInfo(Symbol(),MODE_MINLOT);
   double broker_max=MarketInfo(Symbol(),MODE_MAXLOT);
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   double cap=MathMin(Maxlot,broker_max);
   value=MathMin(value,cap);
   if(value<broker_min) value=broker_min;
   if(step>0) value=MathFloor(value/step+1e-8)*step;
   if(value<broker_min) value=broker_min;
   return NormalizeDouble(value,DigitsLot);
}

double ZeusLot(int n)
{
   return NormalizeLot(lot*MathPow(K_Lot,n)+n*PlusLot);
}

bool ContextOK()
{
   RefreshRates();
   double spread=(Ask-Bid)/Point;
   bool tester=IsTesting();
   bool allowed=IsTradeAllowed();
   bool symbol_allowed=(MarketInfo(Symbol(),MODE_TRADEALLOWED)!=0);
   Decision("CONTEXT","BOTH","CHECK",StringFormat("tester=%s allowed=%s symbol_allowed=%s spread=%.1f",
      tester?"1":"0",allowed?"1":"0",symbol_allowed?"1":"0",spread),0,0,0);

   if(spread>MaxSpread)
   {
      Decision("CONTEXT","BOTH","REJECT","spread_limit",0,0,0);
      return false;
   }
   if(!symbol_allowed)
   {
      Decision("CONTEXT","BOTH","REJECT","symbol_trade_disabled",0,0,0);
      return false;
   }
   if(!allowed && !(tester && BypassTradeContextInTester))
   {
      Decision("CONTEXT","BOTH","REJECT","trade_not_allowed",0,0,0);
      return false;
   }
   return true;
}

bool PendingExists(int type)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsMine()) continue;
      if(OrderType()==type) return true;
   }
   return false;
}

int SendPending(int type,double price,double lots,string comment)
{
   RefreshRates();
   price=NormalizeDouble(price,Digits);
   lots=NormalizeLot(lots);
   int stop_points=(int)MarketInfo(Symbol(),MODE_STOPLEVEL);
   double min_dist=stop_points*Point;

   Decision("EXEC",type==OP_BUYSTOP?"BUY":"SELL","ATTEMPT","OrderSend",price,lots,0);

   if(type==OP_BUYSTOP && price<=Ask+min_dist)
   {
      Decision("EXEC","BUY","REJECT","invalid_buy_stop_distance",price,lots,0);
      return -1;
   }
   if(type==OP_SELLSTOP && price>=Bid-min_dist)
   {
      Decision("EXEC","SELL","REJECT","invalid_sell_stop_distance",price,lots,0);
      return -1;
   }

   ResetLastError();
   int ticket=OrderSend(Symbol(),type,lots,price,0,0,0,comment,Magic,0,clrNONE);
   int err=GetLastError();
   if(ticket<0)
   {
      Decision("EXEC",type==OP_BUYSTOP?"BUY":"SELL","ERROR","OrderSend_error="+IntegerToString(err),price,lots,0);
      return -1;
   }
   Decision("EXEC",type==OP_BUYSTOP?"BUY":"SELL","SUCCESS","ticket="+IntegerToString(ticket),price,lots,0);
   return ticket;
}

void InitialOrders()
{
   if(!ContextOK()) return;
   SideState b,s; State(OP_BUY,b); State(OP_SELL,s);

   if(b.market_count==0 && b.pending_count==0)
   {
      double p=NormalizeDouble(Ask+FirstStep*Point,Digits);
      double l=ZeusLot(0);
      Decision("BUY_INIT","BUY","SEND","count_zero_firststep",p,l,0);
      SendPending(OP_BUYSTOP,p,l,"ZEUS_BUY");
   }
   else
      Decision("BUY_INIT","BUY","HOLD","existing_orders",0,0,b.market_count);

   if(s.market_count==0 && s.pending_count==0)
   {
      double p=NormalizeDouble(Bid-FirstStep*Point,Digits);
      double l=ZeusLot(0);
      Decision("SELL_INIT","SELL","SEND","count_zero_firststep",p,l,0);
      SendPending(OP_SELLSTOP,p,l,"ZEUS_SELL");
   }
   else
      Decision("SELL_INIT","SELL","HOLD","existing_orders",0,0,s.market_count);
}

double BuyCandidate(int n,SideState &s)
{
   double p=(n==0 ? Ask+FirstStep*Point : Ask+MinDistance*Point);
   if(n>0 && s.lowest>0 && p<s.lowest-Step*Point) p=Ask+Step*Point;
   return NormalizeDouble(p,Digits);
}

double SellCandidate(int n,SideState &s)
{
   double p=(n==0 ? Bid-FirstStep*Point : Bid-MinDistance*Point);
   if(n>0 && s.highest>0 && p<s.highest+Step*Point) p=Bid-Step*Point;
   return NormalizeDouble(p,Digits);
}

void LadderBuy()
{
   if(!EnableLadderEntries || !ContextOK()) return;
   SideState s; State(OP_BUY,s); int n=s.market_count;
   if(n<=0) return;
   double p=BuyCandidate(n,s); double l=ZeusLot(n);
   if(PendingExists(OP_BUYSTOP)) return;
   Decision("BUY_LADDER","BUY","SEND","candidate",p,l,n);
   SendPending(OP_BUYSTOP,p,l,"ZEUS_BUY");
}

void LadderSell()
{
   if(!EnableLadderEntries || !ContextOK()) return;
   SideState s; State(OP_SELL,s); int n=s.market_count;
   if(n<=0) return;
   double p=SellCandidate(n,s); double l=ZeusLot(n);
   if(PendingExists(OP_SELLSTOP)) return;
   Decision("SELL_LADDER","SELL","SEND","candidate",p,l,n);
   SendPending(OP_SELLSTOP,p,l,"ZEUS_SELL");
}

void TrailBuy()
{
   if(!EnableTrailing || !ContextOK()) return;
   SideState s; State(OP_BUY,s); int n=s.market_count;
   double p=NormalizeDouble(n==0?Ask+FirstStep*Point:Ask+MinDistance*Point,Digits);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsMine() || OrderType()!=OP_BUYSTOP) continue;
      if(OrderOpenPrice()-StepTrallOrders*Point>p)
      {
         int ticket=OrderTicket(); double lots=OrderLots();
         ResetLastError(); bool ok=OrderModify(ticket,p,0,0,0,clrNONE); int err=GetLastError();
         if(ok) Decision("TRAIL","BUY","MODIFY","trailing",p,lots,n);
         else Decision("TRAIL","BUY","ERROR","OrderModify_error="+IntegerToString(err),p,lots,n);
      }
   }
}

void TrailSell()
{
   if(!EnableTrailing || !ContextOK()) return;
   SideState s; State(OP_SELL,s); int n=s.market_count;
   double p=NormalizeDouble(n==0?Bid-FirstStep*Point:Bid-MinDistance*Point,Digits);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsMine() || OrderType()!=OP_SELLSTOP) continue;
      if(OrderOpenPrice()+StepTrallOrders*Point<p)
      {
         int ticket=OrderTicket(); double lots=OrderLots();
         ResetLastError(); bool ok=OrderModify(ticket,p,0,0,0,clrNONE); int err=GetLastError();
         if(ok) Decision("TRAIL","SELL","MODIFY","trailing",p,lots,n);
         else Decision("TRAIL","SELL","ERROR","OrderModify_error="+IntegerToString(err),p,lots,n);
      }
   }
}

void Cycle()
{
   RefreshRates();
   if(TimeCurrent()==last_cycle) return;
   last_cycle=TimeCurrent();
   InitialOrders();
   LadderBuy();
   LadderSell();
   TrailBuy();
   TrailSell();
}

int OnInit()
{
   Print(PREFIX," V0.2 INIT | Symbol=",Symbol()," Digits=",Digits," Point=",DoubleToString(Point,Digits),
         " Magic=",Magic," FirstStep=",FirstStep," MinDistance=",MinDistance,
         " Step=",Step," Trail=",StepTrallOrders);
   Print(PREFIX," TESTING=",IsTesting()," TRADE_ALLOWED=",IsTradeAllowed(),
         " SYMBOL_TRADE_ALLOWED=",MarketInfo(Symbol(),MODE_TRADEALLOWED),
         " STOPLEVEL=",MarketInfo(Symbol(),MODE_STOPLEVEL),
         " MINLOT=",MarketInfo(Symbol(),MODE_MINLOT)," LOTSTEP=",MarketInfo(Symbol(),MODE_LOTSTEP),
         " MAXLOT=",MarketInfo(Symbol(),MODE_MAXLOT));
   EventSetTimer(MathMax(1,TimerSeconds));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Print(PREFIX," V0.2 DEINIT reason=",reason);
}

void OnTick(){Cycle();}
void OnTimer(){Cycle();}
//+------------------------------------------------------------------+
