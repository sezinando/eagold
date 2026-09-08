//+------------------------------------------------------------------+
//| ZEUS_REPLICA.mq4                                                 |
//| ZEUS Gold Hedge V1.2 - incremental reverse engineering           |
//|                                                                  |
//| V0.2 - STAGE 2: RECONCILIATION ONLY                             |
//|                                                                  |
//| APPROVED BASE                                                     |
//|   V0.1 proved: OnInit -> OnTick -> initial OrderSend             |
//|                                                                  |
//| THIS STAGE                                                       |
//|   - preserve the proven two initial pending orders               |
//|   - inspect current orders every tick                            |
//|   - classify BUY/SELL market and pending orders                  |
//|   - report count and lots                                        |
//|   - detect market-count transitions (activation evidence)        |
//|                                                                  |
//| INTENTIONALLY NOT IMPLEMENTED                                    |
//|   - ladder                                                        |
//|   - trailing                                                      |
//|   - exits                                                         |
//|   - CloseBy                                                       |
//|   - Step / MinDistance candidate creation                        |
//|                                                                  |
//| RULE: Stage 2 must not create any order beyond the two initial   |
//|       orders.                                                     |
//+------------------------------------------------------------------+
#property strict
#property version   "0.2"
#property description "ZEUS Replica V0.2 - Stage 2 reconciliation only"

input int      Magic            = 1001;
input double   Lots             = 0.01;
input int      FirstStep        = 160;
input int      MaxSpread        = 100;
input bool     SendInitialOrders= true;
input bool     EnableLogs       = true;

bool g_first_tick=false;
int  g_prev_buy_market=-1;
int  g_prev_sell_market=-1;

void Log(string text)
{
   if(EnableLogs) Print("ZEUS_REPLICA | ",text);
}

string SideText(int side)
{
   return(side==OP_BUY ? "BUY" : "SELL");
}

bool IsOurOrder()
{
   return(OrderSymbol()==Symbol() && OrderMagicNumber()==Magic);
}

bool IsOurPending(int type)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsOurOrder()) continue;
      if(OrderType()==type) return(true);
   }
   return(false);
}

double NormalizeLots(double value)
{
   double min_lot=MarketInfo(Symbol(),MODE_MINLOT);
   double max_lot=MarketInfo(Symbol(),MODE_MAXLOT);
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);

   value=MathMax(value,min_lot);
   value=MathMin(value,max_lot);

   if(step>0.0)
      value=MathFloor(value/step+1e-8)*step;

   value=MathMax(value,min_lot);
   return(NormalizeDouble(value,2));
}

bool ContextOK()
{
   RefreshRates();

   double spread=(Ask-Bid)/Point;
   if(spread>MaxSpread)
   {
      Log("CONTEXT REJECT | spread="+DoubleToString(spread,1)+
          " MaxSpread="+IntegerToString(MaxSpread));
      return(false);
   }

   if(MarketInfo(Symbol(),MODE_TRADEALLOWED)==0)
   {
      Log("CONTEXT REJECT | symbol trade disabled");
      return(false);
   }

   // Strategy Tester proved OrderSend works without using
   // IsTradeAllowed() as an absolute blocker.
   if(!IsTesting() && !IsTradeAllowed())
   {
      Log("CONTEXT REJECT | trade not allowed");
      return(false);
   }

   return(true);
}

bool BrokerDistanceOK(int type,double price)
{
   RefreshRates();
   double stop_level=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;

   if(type==OP_BUYSTOP && price<=Ask+stop_level)
   {
      Log("SEND REJECT | BUY STOP broker distance");
      return(false);
   }

   if(type==OP_SELLSTOP && price>=Bid-stop_level)
   {
      Log("SEND REJECT | SELL STOP broker distance");
      return(false);
   }

   return(true);
}

bool SendInitial(int type)
{
   if(!ContextOK()) return(false);

   RefreshRates();

   double lots=NormalizeLots(Lots);
   double price=0.0;
   string side="";

   if(type==OP_BUYSTOP)
   {
      price=NormalizeDouble(Ask+FirstStep*Point,Digits);
      side="BUY STOP";
   }
   else if(type==OP_SELLSTOP)
   {
      price=NormalizeDouble(Bid-FirstStep*Point,Digits);
      side="SELL STOP";
   }
   else return(false);

   if(!BrokerDistanceOK(type,price)) return(false);

   Log("SEND ATTEMPT | side="+side+
       " price="+DoubleToString(price,Digits)+
       " lots="+DoubleToString(lots,2));

   ResetLastError();
   int ticket=OrderSend(Symbol(),type,lots,price,0,0,0,
                        "ZEUS_REPLICA",Magic,0,clrNONE);
   int error=GetLastError();

   if(ticket<0)
   {
      Log("SEND ERROR | side="+side+
          " error="+IntegerToString(error));
      return(false);
   }

   Log("SEND SUCCESS | side="+side+
       " ticket="+IntegerToString(ticket)+
       " price="+DoubleToString(price,Digits)+
       " lots="+DoubleToString(lots,2));
   return(true);
}

void EnsureInitialOrders()
{
   if(!SendInitialOrders) return;

   // Preserve V0.1 behavior: initial orders exist only when the
   // corresponding side has no market/pending order.
   if(!IsOurPending(OP_BUYSTOP))
   {
      bool buy_market=false;
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
         if(!IsOurOrder()) continue;
         if(OrderType()==OP_BUY || OrderType()==OP_BUYLIMIT)
         {
            buy_market=true;
            break;
         }
      }
      if(!buy_market) SendInitial(OP_BUYSTOP);
   }

   if(!IsOurPending(OP_SELLSTOP))
   {
      bool sell_market=false;
      for(int j=OrdersTotal()-1;j>=0;j--)
      {
         if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
         if(!IsOurOrder()) continue;
         if(OrderType()==OP_SELL || OrderType()==OP_SELLLIMIT)
         {
            sell_market=true;
            break;
         }
      }
      if(!sell_market) SendInitial(OP_SELLSTOP);
   }
}

void Reconcile()
{
   int buy_market=0;
   int sell_market=0;
   int buy_pending=0;
   int sell_pending=0;
   double buy_market_lots=0.0;
   double sell_market_lots=0.0;
   double buy_pending_lots=0.0;
   double sell_pending_lots=0.0;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(!IsOurOrder()) continue;

      int type=OrderType();
      double order_lots=OrderLots();

      if(type==OP_BUY)
      {
         buy_market++;
         buy_market_lots+=order_lots;
      }
      else if(type==OP_SELL)
      {
         sell_market++;
         sell_market_lots+=order_lots;
      }
      else if(type==OP_BUYSTOP || type==OP_BUYLIMIT)
      {
         buy_pending++;
         buy_pending_lots+=order_lots;
      }
      else if(type==OP_SELLSTOP || type==OP_SELLLIMIT)
      {
         sell_pending++;
         sell_pending_lots+=order_lots;
      }
   }

   bool buy_changed=(g_prev_buy_market>=0 && buy_market!=g_prev_buy_market);
   bool sell_changed=(g_prev_sell_market>=0 && sell_market!=g_prev_sell_market);

   if(g_prev_buy_market<0 || g_prev_sell_market<0 || buy_changed || sell_changed)
   {
      Log("RECONCILE | BUY market="+IntegerToString(buy_market)+
          " pending="+IntegerToString(buy_pending)+
          " market_lots="+DoubleToString(buy_market_lots,2)+
          " pending_lots="+DoubleToString(buy_pending_lots,2)+
          " | SELL market="+IntegerToString(sell_market)+
          " pending="+IntegerToString(sell_pending)+
          " market_lots="+DoubleToString(sell_market_lots,2)+
          " pending_lots="+DoubleToString(sell_pending_lots,2));
   }

   if(buy_changed)
      Log("ACTIVATION EVIDENCE | BUY market_count " +
          IntegerToString(g_prev_buy_market)+" -> "+IntegerToString(buy_market));

   if(sell_changed)
      Log("ACTIVATION EVIDENCE | SELL market_count " +
          IntegerToString(g_prev_sell_market)+" -> "+IntegerToString(sell_market));

   g_prev_buy_market=buy_market;
   g_prev_sell_market=sell_market;
}

int OnInit()
{
   Log("============================================================");
   Log("INIT | ZEUS_REPLICA V0.2 | STAGE 2 RECONCILIATION");
   Log("INIT | Symbol="+Symbol()+" Magic="+IntegerToString(Magic));
   Log("INIT | testing="+(IsTesting()?"true":"false")+
       " digits="+IntegerToString(Digits)+
       " point="+DoubleToString(Point,Digits));
   Log("INIT | FirstStep="+IntegerToString(FirstStep)+
       " Lots="+DoubleToString(Lots,2)+
       " MaxSpread="+IntegerToString(MaxSpread));
   Log("INIT | NO LADDER | NO TRAILING | NO EXITS");
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

   // Stage 2 order of operations:
   // 1) reconcile current state
   // 2) preserve the proven initial-order behavior
   // No ladder or other order creation is allowed here.
   Reconcile();
   EnsureInitialOrders();
}

//+------------------------------------------------------------------+
