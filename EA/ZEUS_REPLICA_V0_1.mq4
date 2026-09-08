//+------------------------------------------------------------------+
//| ZEUS_REPLICA_V0_1.mq4                                           |
//| Controlled reverse-engineering replica - V0.1                    |
//|                                                                  |
//| Scope:                                                           |
//|   - market/basket reconciliation                                 |
//|   - independent BUY / SELL pending engines                       |
//|   - FirstStep / MinDistance / Step fallback                     |
//|   - empirical lot engine                                         |
//|   - BUY STOP / SELL STOP                                         |
//|   - pending trailing                                             |
//|   - decision/event telemetry                                     |
//|                                                                  |
//| Intentionally NOT implemented in V0.1:                          |
//|   - StopProfit                                                   |
//|   - CloseBuySell                                                 |
//|   - Global CloseAll / Homeopathy                                 |
//|   - MaxLoss / StopLoss                                           |
//|   - CloseBy orchestration                                        |
//|                                                                  |
//| These layers remain isolated until validated against the         |
//| controlled Zeus Gold Hedge V1.2 logs.                             |
//+------------------------------------------------------------------+
#property strict
#property version   "0.1"
#property description "ZEUS reverse-engineering replica V0.1"

input int      Magic               = 1001;
input double   StopProfit          = 20.0;     // reserved V0.2+
input double   StopLoss            = 0.0;      // reserved V0.4+
input double   lot                 = 0.01;
input double   K_Lot               = 1.20;
input int      DigitsLot           = 2;
input int      CloseAll            = 4;        // reserved V0.4+
input double   PlusLot             = 0.01;
input double   Maxlot              = 0.62;
input int      MaxSpread           = 100;
input int      NextTime            = 0;
input int      FirstStep           = 160;
input int      MinDistance         = 340;
input int      TwoMinDistance      = 80;       // observed inactive in controlled V1.2 tests
input int      StepTrallOrders     = 50;
input int      Step                = 80;
input int      TwoStep             = 90;       // observed inactive in controlled V1.2 tests
input double   MaxLoss             = 100000;
input double   MaxLossCloseAll     = 100;
input int      Totals              = 2000;
input int      Leverage            = 100;

input bool     EnableLadderEntries = true;
input bool     EnableTrailing      = true;
input bool     EnableTelemetry     = true;
input bool     DeleteForeignPending= false;
input int      TimerSeconds        = 1;

string g_prefix = "ZEUS_REPLICA";
datetime g_last_cycle = 0;

struct SideState
{
   int    market_count;
   int    pending_count;
   double market_lots;
   double pending_lots;
   double lowest;
   double highest;
   double floating_profit;
};

//+------------------------------------------------------------------+
void LogDecision(string stage,string side,string action,string reason,double price,double lots,int count)
{
   if(!EnableTelemetry) return;
   Print(g_prefix,"|DECISION|",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
         "|stage=",stage,"|side=",side,"|action=",action,
         "|reason=",reason,"|price=",DoubleToString(price,Digits),
         "|lots=",DoubleToString(lots,DigitsLot),"|count=",count);
}

//+------------------------------------------------------------------+
void LogEvent(string event_name,int ticket,string side,double price,double lots,string detail)
{
   if(!EnableTelemetry) return;
   Print(g_prefix,"|EVENT|",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
         "|event=",event_name,"|ticket=",ticket,"|side=",side,
         "|price=",DoubleToString(price,Digits),"|lots=",DoubleToString(lots,DigitsLot),
         "|detail=",detail);
}

//+------------------------------------------------------------------+
string CsvName(string suffix)
{
   return(g_prefix+"_"+suffix+".csv");
}

//+------------------------------------------------------------------+
void WriteCsv(string suffix,string line)
{
   if(!EnableTelemetry) return;
   int h=FileOpen(CsvName(suffix),FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(h==INVALID_HANDLE) return;
   FileSeek(h,0,SEEK_END);
   FileWriteString(h,line+"\r\n");
   FileClose(h);
}

//+------------------------------------------------------------------+
string SideName(int type)
{
   if(type==OP_BUY || type==OP_BUYSTOP || type==OP_BUYLIMIT) return "BUY";
   if(type==OP_SELL || type==OP_SELLSTOP || type==OP_SELLLIMIT) return "SELL";
   return "OTHER";
}

//+------------------------------------------------------------------+
bool IsOurOrder()
{
   return(OrderSymbol()==Symbol() && OrderMagicNumber()==Magic);
}

//+------------------------------------------------------------------+
void GetSideState(int side,SideState &s)
{
   s.market_count=0;
   s.pending_count=0;
   s.market_lots=0.0;
   s.pending_lots=0.0;
   s.lowest=DBL_MAX;
   s.highest=-DBL_MAX;
   s.floating_profit=0.0;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsOurOrder()) continue;

      int type=OrderType();
      bool is_market=(type==OP_BUY || type==OP_SELL);
      bool is_side=(side==OP_BUY ? (type==OP_BUY || type==OP_BUYSTOP || type==OP_BUYLIMIT)
                                 : (type==OP_SELL || type==OP_SELLSTOP || type==OP_SELLLIMIT));
      if(!is_side) continue;

      double p=OrderOpenPrice();
      if(p<s.lowest) s.lowest=p;
      if(p>s.highest) s.highest=p;

      if(is_market)
      {
         s.market_count++;
         s.market_lots+=OrderLots();
         s.floating_profit+=OrderProfit()+OrderSwap()+OrderCommission();
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

//+------------------------------------------------------------------+
int MarketCount(int side)
{
   SideState s; GetSideState(side,s); return s.market_count;
}

//+------------------------------------------------------------------+
double NormalizeLot(double v)
{
   double minlot=MarketInfo(Symbol(),MODE_MINLOT);
   double maxlot=MarketInfo(Symbol(),MODE_MAXLOT);
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   double cap=MathMin(Maxlot,maxlot);
   if(v>cap) v=cap;
   if(v<minlot) v=minlot;
   if(step>0.0) v=MathFloor(v/step+0.0000001)*step;
   return NormalizeDouble(v,DigitsLot);
}

//+------------------------------------------------------------------+
double ZeusLot(int n)
{
   double v=lot*MathPow(K_Lot,n)+n*PlusLot;
   return NormalizeLot(v);
}

//+------------------------------------------------------------------+
double BuyCandidate(int count,SideState &s)
{
   double candidate;
   if(count==0) candidate=Ask+FirstStep*Point;
   else         candidate=Ask+MinDistance*Point;

   // Empirical Step fallback observed in the controlled logs.
   // For BUY, the fallback is only meaningful when the MinDistance
   // candidate would be below the BUY-side lower boundary by Step.
   if(count>0 && s.lowest>0.0 && candidate < s.lowest-Step*Point)
      candidate=Ask+Step*Point;

   return NormalizeDouble(candidate,Digits);
}

//+------------------------------------------------------------------+
double SellCandidate(int count,SideState &s)
{
   double candidate;
   if(count==0) candidate=Bid-FirstStep*Point;
   else         candidate=Bid-MinDistance*Point;

   // Empirical Step fallback observed in the controlled logs.
   if(count>0 && s.highest>0.0 && candidate < s.highest+Step*Point)
      candidate=Bid-Step*Point;

   return NormalizeDouble(candidate,Digits);
}

//+------------------------------------------------------------------+
bool SpreadOK()
{
   double spread_points=(Ask-Bid)/Point;
   if(spread_points>MaxSpread)
   {
      LogDecision("CONTEXT","BOTH","REJECT","spread_limit",0,0,0);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool TradeContextOK()
{
   if(!IsTradeAllowed())
   {
      LogDecision("CONTEXT","BOTH","REJECT","trade_not_allowed",0,0,0);
      return false;
   }
   if(!SpreadOK()) return false;
   if(MarketInfo(Symbol(),MODE_TRADEALLOWED)==0)
   {
      LogDecision("CONTEXT","BOTH","REJECT","symbol_trade_disabled",0,0,0);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool HasPendingType(int type)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsOurOrder()) continue;
      if(OrderType()==type) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
int SendPending(int type,double price,double lots,string comment)
{
   RefreshRates();
   price=NormalizeDouble(price,Digits);
   lots=NormalizeLot(lots);

   double stop_level=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(type==OP_BUYSTOP && price<Ask+stop_level)
   {
      LogDecision("EXEC","BUY","REJECT","broker_stop_level",price,lots,0);
      return -1;
   }
   if(type==OP_SELLSTOP && price>Bid-stop_level)
   {
      LogDecision("EXEC","SELL","REJECT","broker_stop_level",price,lots,0);
      return -1;
   }

   ResetLastError();
   int ticket=OrderSend(Symbol(),type,lots,price,0,0,0,comment,Magic,0,clrNONE);
   int err=GetLastError();
   if(ticket<0)
   {
      LogDecision("EXEC",type==OP_BUYSTOP?"BUY":"SELL","ERROR","OrderSend_"+IntegerToString(err),price,lots,0);
      return -1;
   }

   LogEvent("PENDING_CREATE",ticket,type==OP_BUYSTOP?"BUY":"SELL",price,lots,comment);
   WriteCsv("EVENTS",IntegerToString((int)TimeCurrent())+";PENDING_CREATE;"+
            IntegerToString(ticket)+";"+(type==OP_BUYSTOP?"BUY":"SELL")+";"+
            DoubleToString(price,Digits)+";"+DoubleToString(lots,DigitsLot));
   return ticket;
}

//+------------------------------------------------------------------+
void EnsureInitialOrders()
{
   if(!TradeContextOK()) return;

   SideState buy,sell;
   GetSideState(OP_BUY,buy);
   GetSideState(OP_SELL,sell);

   if(buy.market_count==0 && buy.pending_count==0 && !HasPendingType(OP_BUYSTOP))
   {
      double p=NormalizeDouble(Ask+FirstStep*Point,Digits);
      double l=ZeusLot(0);
      LogDecision("BUY_INIT","BUY","SEND","count_zero_firststep",p,l,0);
      SendPending(OP_BUYSTOP,p,l,"ZEUS_BUY");
   }

   if(sell.market_count==0 && sell.pending_count==0 && !HasPendingType(OP_SELLSTOP))
   {
      double p=NormalizeDouble(Bid-FirstStep*Point,Digits);
      double l=ZeusLot(0);
      LogDecision("SELL_INIT","SELL","SEND","count_zero_firststep",p,l,0);
      SendPending(OP_SELLSTOP,p,l,"ZEUS_SELL");
   }
}

//+------------------------------------------------------------------+
bool CreationGateBuy(double candidate,double lots,SideState &s)
{
   // Conservative V0.1 gate. Exact imbalance/spacing formula remains
   // isolated because the reverse-engineering logs do not uniquely
   // identify every rejection condition yet.
   if(s.pending_count>0)
   {
      // Never stack an identical BUY STOP intent in the same cycle.
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
         if(!IsOurOrder()) continue;
         if(OrderType()!=OP_BUYSTOP) continue;
         if(MathAbs(OrderOpenPrice()-candidate)<=Point*0.5) return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
bool CreationGateSell(double candidate,double lots,SideState &s)
{
   if(s.pending_count>0)
   {
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
         if(!IsOurOrder()) continue;
         if(OrderType()!=OP_SELLSTOP) continue;
         if(MathAbs(OrderOpenPrice()-candidate)<=Point*0.5) return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
void EvaluateBuy()
{
   if(!EnableLadderEntries || !TradeContextOK()) return;

   SideState s; GetSideState(OP_BUY,s);
   int n=s.market_count;
   if(n<=0) return;

   double candidate=BuyCandidate(n,s);
   double lots=ZeusLot(n);

   if(!CreationGateBuy(candidate,lots,s))
   {
      LogDecision("BUY_EVAL","BUY","REJECT","creation_gate",candidate,lots,n);
      return;
   }

   LogDecision("BUY_EVAL","BUY","SEND","normal_or_step_candidate",candidate,lots,n);
   SendPending(OP_BUYSTOP,candidate,lots,"ZEUS_BUY");
}

//+------------------------------------------------------------------+
void EvaluateSell()
{
   if(!EnableLadderEntries || !TradeContextOK()) return;

   SideState s; GetSideState(OP_SELL,s);
   int n=s.market_count;
   if(n<=0) return;

   double candidate=SellCandidate(n,s);
   double lots=ZeusLot(n);

   if(!CreationGateSell(candidate,lots,s))
   {
      LogDecision("SELL_EVAL","SELL","REJECT","creation_gate",candidate,lots,n);
      return;
   }

   LogDecision("SELL_EVAL","SELL","SEND","normal_or_step_candidate",candidate,lots,n);
   SendPending(OP_SELLSTOP,candidate,lots,"ZEUS_SELL");
}

//+------------------------------------------------------------------+
void TrailBuy()
{
   if(!EnableTrailing || !TradeContextOK()) return;

   SideState s; GetSideState(OP_BUY,s);
   int n=s.market_count;
   double candidate;
   if(n==0) candidate=Ask+FirstStep*Point;
   else     candidate=Ask+MinDistance*Point;
   candidate=NormalizeDouble(candidate,Digits);

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsOurOrder() || OrderType()!=OP_BUYSTOP) continue;

      double oldp=OrderOpenPrice();
      if(oldp-StepTrallOrders*Point>candidate)
      {
         ResetLastError();
         bool ok=OrderModify(OrderTicket(),candidate,0,0,0,clrNONE);
         int err=GetLastError();
         if(ok)
         {
            LogEvent("PENDING_MODIFY",OrderTicket(),"BUY",candidate,OrderLots(),"trailing");
            WriteCsv("EVENTS",IntegerToString((int)TimeCurrent())+";PENDING_MODIFY;"+
                     IntegerToString(OrderTicket())+";BUY;"+DoubleToString(candidate,Digits)+";"+
                     DoubleToString(OrderLots(),DigitsLot));
         }
         else
            LogDecision("TRAIL","BUY","ERROR","OrderModify_"+IntegerToString(err),candidate,OrderLots(),n);
      }
   }
}

//+------------------------------------------------------------------+
void TrailSell()
{
   if(!EnableTrailing || !TradeContextOK()) return;

   SideState s; GetSideState(OP_SELL,s);
   int n=s.market_count;
   double candidate;
   if(n==0) candidate=Bid-FirstStep*Point;
   else     candidate=Bid-MinDistance*Point;
   candidate=NormalizeDouble(candidate,Digits);

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsOurOrder() || OrderType()!=OP_SELLSTOP) continue;

      double oldp=OrderOpenPrice();
      if(oldp+StepTrallOrders*Point<candidate)
      {
         ResetLastError();
         bool ok=OrderModify(OrderTicket(),candidate,0,0,0,clrNONE);
         int err=GetLastError();
         if(ok)
         {
            LogEvent("PENDING_MODIFY",OrderTicket(),"SELL",candidate,OrderLots(),"trailing");
            WriteCsv("EVENTS",IntegerToString((int)TimeCurrent())+";PENDING_MODIFY;"+
                     IntegerToString(OrderTicket())+";SELL;"+DoubleToString(candidate,Digits)+";"+
                     DoubleToString(OrderLots(),DigitsLot));
         }
         else
            LogDecision("TRAIL","SELL","ERROR","OrderModify_"+IntegerToString(err),candidate,OrderLots(),n);
      }
   }
}

//+------------------------------------------------------------------+
void DeleteForeignPendingOrders()
{
   if(!DeleteForeignPending) return;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      int type=OrderType();
      if(type!=OP_BUYSTOP && type!=OP_SELLSTOP && type!=OP_BUYLIMIT && type!=OP_SELLLIMIT) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=Magic) continue;
      // Placeholder: deletion is intentionally not enabled by default.
   }
}

//+------------------------------------------------------------------+
void ReconcileAndLog()
{
   SideState b,s;
   GetSideState(OP_BUY,b);
   GetSideState(OP_SELL,s);

   if(EnableTelemetry)
   {
      string line=TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+";"+
                  IntegerToString(b.market_count)+";"+IntegerToString(b.pending_count)+";"+
                  DoubleToString(b.market_lots,DigitsLot)+";"+DoubleToString(b.floating_profit,2)+";"+
                  IntegerToString(s.market_count)+";"+IntegerToString(s.pending_count)+";"+
                  DoubleToString(s.market_lots,DigitsLot)+";"+DoubleToString(s.floating_profit,2)+";"+
                  DoubleToString(Bid,Digits)+";"+DoubleToString(Ask,Digits);
      WriteCsv("SNAPSHOT",line);
   }
}

//+------------------------------------------------------------------+
void EngineCycle()
{
   RefreshRates();
   if(TimeCurrent()==g_last_cycle) return;
   g_last_cycle=TimeCurrent();

   // Structural pipeline V0.1:
   // MARKET -> RECONCILE -> INITIAL -> BUY -> SELL -> TRAILING -> RECONCILE
   ReconcileAndLog();
   DeleteForeignPendingOrders();
   EnsureInitialOrders();
   EvaluateBuy();
   EvaluateSell();
   TrailBuy();
   TrailSell();
   ReconcileAndLog();
}

//+------------------------------------------------------------------+
int OnInit()
{
   Print(g_prefix," V0.1 INIT | symbol=",Symbol()," | magic=",Magic,
         " | FirstStep=",FirstStep," | MinDistance=",MinDistance,
         " | Step=",Step," | Trail=",StepTrallOrders);
   EventSetTimer(MathMax(1,TimerSeconds));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print(g_prefix," V0.1 DEINIT | reason=",reason);
}

//+------------------------------------------------------------------+
void OnTick()
{
   EngineCycle();
}

//+------------------------------------------------------------------+
void OnTimer()
{
   EngineCycle();
}
//+------------------------------------------------------------------+
