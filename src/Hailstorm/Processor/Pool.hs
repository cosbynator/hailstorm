module Hailstorm.Processor.Pool
( downstreamPoolConsumer
) where

import Data.ByteString.Char8 ()
import Hailstorm.UserFormula
import Hailstorm.Payload
import Hailstorm.Processor
import Hailstorm.Topology
import Network.Simple.TCP
import Network.Socket(socketToHandle)
import Pipes
import System.IO
import qualified Data.Map as Map

type Host = String
type Port = String

-- | @poolConnect address handleMap@ will return a handle for communication
-- with a processor, using an existing handle if one exists in
-- @handleMap@, creating a new connection to the host otherwise.
poolConnect :: (Host, Port) -> Map.Map (Host, Port) Handle -> IO Handle
poolConnect (host, port) handleMap = case Map.lookup (host, port) handleMap of
    Just h -> return h
    Nothing -> connect host port $ \(s, _) -> socketToHandle s WriteMode

-- | Produces a single Consumer comprised of all stream consumer layers of
-- the topology (bolts and sinks) that subscribe to a emitting processor's
-- stream. Payloads received by the consumer are sent to the next layer in
-- the topology.
downstreamPoolConsumer :: Topology t
                   => ProcessorName
                   -> t
                   -> UserFormula k v
                   -> Consumer (Payload k v) IO ()
downstreamPoolConsumer processorName topology uformula = emitToNextLayer Map.empty
  where
    emitToNextLayer connPool = do
        payload <- await
        let sendAddresses = downstreamAddresses topology processorName payload
            getHandle addressTuple = lift $ poolConnect addressTuple connPool
            emitToHandle h = (lift . hPutStrLn h) $
                serialize uformula (payloadTuple payload) ++ "\1" ++
                    show (payloadClock payload)
        newHandles <- mapM getHandle sendAddresses
        mapM_ emitToHandle newHandles
        let newPool = Map.fromList $ zip sendAddresses newHandles
        emitToNextLayer $ Map.union newPool connPool
