//+------------------------------------------------------------------+
//| ZEUS_REPLICA.mq4                                                 |
//| ZEUS Gold Hedge V1.2 - incremental reverse engineering           |
//|                                                                  |
//| V0.3 - STAGE 3: FIRST BUY LADDER ONLY                           |
//|                                                                  |
//| APPROVED BASE                                                    |
//|   V0.1/V0.2.1: initial BUY STOP + SELL STOP proven              |
//|   V0.2.1: reconciliation proven                                  |
//|                                                                  |
//| THIS STAGE                                                       |
//|   - preserve proven bootstrap path                               |
//|   - detect BUY activation                                       |
//|   - when exactly one BUY market position exists and no BUY STOP  |
//|     exists, create the first BUY ladder order                    |
//|   - price = Ask + MinDistance                                    |
//|   - lot remains the fixed Lots input in this isolated stage      |
//|                                                                  |
//| INTENTIONALLY NOT IMPLEMENTED                                    |
//|   - SELL ladder                                                  |
//|   - lot progression / K_Lot / PlusLot                            |
//|   - Step fallback                                                |
//|   - trailing                                                     |
//|   - exits / CloseBy / CloseAll                                   |
//+------------------------------------------------------------------+
#property strict
#property version   "0.3"
#property description "ZEUS Replica V0.3 - Stage 3 first BUY ladder only"

input int      Magic             = 1001;
input double   Lots              = 0.01;
input int      FirstStep         = 160;
input int      MinDistance       = 340;
input int      MaxSpread         = 100;
input bool     SendInitialOrders = true;
input bool     EnableLogs        = true;

bool g_first_tick=false;
int  g_prev_buy_market=-1;
int  g_prev_sell_market=-1;

void Log(string text)
{
   if(EnableLogs)
      Print("ZEUS_REPLICA | ",text);
}

string BoolText(bool value)
{
   return(value ? "true" : "false");
}

bool IsOurOrder()
{
   return(OrderSymbol()==Symbol() && OrderMagicNumber()==Magic);
}

bool IsOurPending(int type)
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;

      if(!IsOurOrder())
         continue;

      if(OrderType()==type)
         return(true);
   }

   return(false);
}

void PrintEnvironment()
{
   RefreshRates();

   double spread_points=0.0;
   if(Point>0.0)
      spread_points=(Ask-Bid)/Point;

   Log("ENV | testing="+BoolText(IsTesting())+
       " symbol="+Symbol()+
       " period="+IntegerToString(Period())+
       " digits="+IntegerToString(Digits)+
       " point="+DoubleToString(Point,Digits));

   Log("ENV | bid="+DoubleToString(Bid,Digits)+
       " ask="+DoubleToString(Ask,Digits)+
       " spread_points="+DoubleToString(spread_points,1));

   Log("ENV | trade_allowed="+BoolText(IsTradeAllowed())+
       " symbol_trade_allowed="+DoubleToString(MarketInfo(Symbol(),MODE_TRADEALLOWED),0));

   Log("ENV | stop_level="+DoubleToString(MarketInfo(Symbol(),MODE_STOPLEVEL),0)+
       " freeze_level="+DoubleToString(MarketInfo(Symbol(),MODE_FREEZELEVEL),0));

   Log("ENV | min_lot="+DoubleToString(MarketInfo(Symbol(),MODE_MINLOT),2)+
       " lot_step="+DoubleToString(MarketInfo(Symbol(),MODE_LOTSTEP),2)+
       " max_lot="+DoubleToString(MarketInfo(Symbol(),MODE_MAXLOT),2));
}

double NormalizeLots(double value)
{
   double min_lot  = MarketInfo(Symbol(),MODE_MINLOT);
   double max_lot  = MarketInfo(Symbol(),MODE_MAXLOT);
   double lot_step = MarketInfo(Symbol(),MODE_LOTSTEP);

   if(value<min_lot)
      value=min_lot;

   if(value>max_lot)
      value=max_lot;

   if(lot_step>0.0)
      value=MathFloor(value/lot_step+1e-8)*lot_step;

   if(value<min_lot)
      value=min_lot;

   return(NormalizeDouble(value,2));
}

// Proven initial-order execution path. No new trade-permission gate is
// inserted between the first tick and OrderSend.
bool SendInitial(int type)
{
   RefreshRates();

   double spread_points=(Ask-Bid)/Point;
   if(spread_points>MaxSpread)
   {
      Log("SEND | REJECT | spread="+DoubleToString(spread_points,1)+
          " > MaxSpread="+IntegerToString(MaxSpread));
      return(false);
   }

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
   else
   {
      Log("SEND | ERROR | unsupported order type");
      return(false);
   }

   double stop_level=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;

   if(type==OP_BUYSTOP && price<=Ask+stop_level)
   {
      Log("SEND | REJECT | BUY STOP distance below broker stop level | price="+
          DoubleToString(price,Digits)+" ask="+DoubleToString(Ask,Digits));
      return(false);
   }

   if(type==OP_SELLSTOP && price>=Bid-stop_level)
   {
      Log("SEND | REJECT | SELL STOP distance below broker stop level | price="+
          DoubleToString(price,Digits)+" bid="+DoubleToString(Bid,Digits));
      return(false);
   }

   Log("SEND | ATTEMPT | side="+side+
       " lots="+DoubleToString(lots,2)+
       " price="+DoubleToString(price,Digits));

   ResetLastError();
   int ticket=OrderSend(Symbol(),type,lots,price,0,0,0,
                        "ZEUS_REPLICA_BOOT",Magic,0,clrNONE);
   int error=GetLastError();

   if(ticket<0)
   {
      Log("SEND | ERROR | side="+side+
          " error="+IntegerToString(error)+
          " price="+DoubleToString(price,Digits)+
          " lots="+DoubleToString(lots,2));
      return(false);
   }

   Log("SEND | SUCCESS | side="+side+
       " ticket="+IntegerToString(ticket)+
       " price="+DoubleToString(price,Digits)+
       " lots="+DoubleToString(lots,2));

   return(true);
}

void BootOrders()
{
   if(!SendInitialOrders)
   {
      Log("BOOT | order sending disabled by input");
      return;
   }

   if(!IsOurPending(OP_BUYSTOP))
      SendInitial(OP_BUYSTOP);
   else
      Log("BOOT | BUY STOP already exists");

   if(!IsOurPending(OP_SELLSTOP))
      SendInitial(OP_SELLSTOP);
   else
      Log("BOOT | SELL STOP already exists");
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

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;

      if(!IsOurOrder())
         continue;

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

   Log("RECONCILE | BUY market="+IntegerToString(buy_market)+
       " pending="+IntegerToString(buy_pending)+
       " market_lots="+DoubleToString(buy_market_lots,2)+
       " pending_lots="+DoubleToString(buy_pending_lots,2)+
       " | SELL market="+IntegerToString(sell_market)+
       " pending="+IntegerToString(sell_pending)+
       " market_lots="+DoubleToString(sell_market_lots,2)+
       " pending_lots="+DoubleToString(sell_pending_lots,2));

   if(buy_changed)
      Log("ACTIVATION EVIDENCE | BUY market_count "+
          IntegerToString(g_prev_buy_market)+" -> "+IntegerToString(buy_market));

   if(sell_changed)
      Log("ACTIVATION EVIDENCE | SELL market_count "+
          IntegerToString(g_prev_sell_market)+" -> "+IntegerToString(sell_market));

   g_prev_buy_market=buy_market;
   g_prev_sell_market=sell_market;
}

// Stage 3 isolated BUY ladder.
// Hypothesis: after the initial BUY STOP activates, when exactly one
// BUY market position exists and no BUY STOP remains, create one BUY
// STOP at Ask + MinDistance. The lot is intentionally fixed at Lots.
bool SendFirstBuyLadder()
{
   RefreshRates();

   double spread_points=(Ask-Bid)/Point;
   if(spread_points>MaxSpread)
   {
      Log("BUY LADDER | REJECT | spread="+DoubleToString(spread_points,1)+
          " > MaxSpread="+IntegerToString(MaxSpread));
      return(false);
   }

   double lots=NormalizeLots(Lots);
   double price=NormalizeDouble(Ask+MinDistance*Point,Digits);
   double stop_level=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;

   if(price<=Ask+stop_level)
   {
      Log("BUY LADDER | REJECT | broker distance | price="+
          DoubleToString(price,Digits)+" ask="+DoubleToString(Ask,Digits)+
          " stop_level="+DoubleToString(stop_level,Digits));
      return(false);
   }

   Log("BUY LADDER | ATTEMPT | n=1 price="+
       DoubleToString(price,Digits)+
       " lots="+DoubleToString(lots,2)+
       " MinDistance="+IntegerToString(MinDistance));

   ResetLastError();
   int ticket=OrderSend(Symbol(),OP_BUYSTOP,lots,price,0,0,0,
                        "ZEUS_REPLICA_BUY_L1",Magic,0,clrNONE);
   int error=GetLastError();

   if(ticket<0)
   {
      Log("BUY LADDER | ERROR | error="+IntegerToString(error)+
          " price="+DoubleToString(price,Digits)+
          " lots="+DoubleToString(lots,2));
      return(false);
   }

   Log("BUY LADDER | SUCCESS | ticket="+IntegerToString(ticket)+
       " price="+DoubleToString(price,Digits)+
       " lots="+DoubleToString(lots,2));
   return(true);
}

void ProcessBuyLadder()
{
   int buy_market=0;
   int buy_pending=0;

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;

      if(!IsOurOrder())
         continue;

      int type=OrderType();
      if(type==OP_BUY)
         buy_market++;
      else if(type==OP_BUYSTOP)
         buy_pending++;
   }

   // Exactly one market BUY and no BUY STOP is the only Stage 3 trigger.
   if(buy_market==1 && buy_pending==0)
   {
      Log("BUY LADDER | TRIGGER | market_count=1 pending_count=0");
      SendFirstBuyLadder();
   }
}

int OnInit()
{
   Log("============================================================");
   Log("INIT | ZEUS_REPLICA V0.3 | STAGE 3 FIRST BUY LADDER");
   Log("INIT | Symbol="+Symbol()+" Magic="+IntegerToString(Magic));
   PrintEnvironment();
   Log("INIT | FirstStep="+IntegerToString(FirstStep)+
       " MinDistance="+IntegerToString(MinDistance)+
       " Lots="+DoubleToString(Lots,2)+
       " MaxSpread="+IntegerToString(MaxSpread));
   Log("INIT | BUY LADDER ONLY | NO SELL LADDER | NO TRAILING | NO EXITS");
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

      Log("============================================================");
      Log("TICK | FIRST TICK RECEIVED");
      Log("TICK | Time="+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
      Log("TICK | Bid="+DoubleToString(Bid,Digits)+
          " Ask="+DoubleToString(Ask,Digits));
      Log("TICK | OnTick lifecycle confirmed");
      Log("============================================================");

      // Preserve the exact proven bootstrap path.
      BootOrders();
      return;
   }

   // Stage 2 reconciliation remains intact.
   Reconcile();

   // Stage 3: only the first BUY ladder order.
   ProcessBuyLadder();
}

//+------------------------------------------------------------------+
