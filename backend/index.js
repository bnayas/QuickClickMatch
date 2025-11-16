const http = require('http');
const url = require('url');
const WebSocket = require('ws');
const DEFAULT_PORT = 8080;
const envPort = parseInt(process.env.PORT ?? '', 10);
const PORT = Number.isFinite(envPort) ? envPort : DEFAULT_PORT;

if (!Number.isFinite(envPort) && process.env.PORT) {
  console.warn(`Invalid PORT value "${process.env.PORT}", falling back to ${DEFAULT_PORT}`);
}
const fs = require('fs');
const path = require('path');

let wsCounter = 0;

// Store WebSocket clients by userId - now properly handling multiple connections per user
const clients = new Map(); // userId -> Set of WebSocket connections

// --- NEW Identity Model ---
// Ground truth for user data, indexed by the permanent userId
const usersByUserId = new Map(); // userId -> { userName }
// Searchable map of display names, for finding users
const usersByUserName = new Map(); // userName -> { userId }
// --- End NEW Identity Model ---

// Store invites: inviteId -> { id, fromUserId, fromUserName, toUserId, toUserName, timestamp, status }
const invites = new Map();

// Store pending invites per user: userId -> Set(inviteId)
const pendingInvitesByUser = new Map();

// Store blocked users: userId -> Set(blockedUserId)
const blockedUsers = new Map();

// Current active pair (single game at a time)
let activePair = null; // { a: userId, b: userId, seed }

// Connection tracking
const connectionsByWsId = new Map(); // wsId -> { userId, ws }

const TEMP_USER_PREFIX = 'guest_';

function isTemporaryUserId(userId) {
  if (typeof userId !== 'string') return true;
  return userId.trim().startsWith(TEMP_USER_PREFIX);
}

function isRegisteredUserId(userId) {
  return !isTemporaryUserId(userId);
}

function json(res, statusCode, body) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
  });
  res.end(JSON.stringify(body));
}

function generateInviteId() {
  return 'inv_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
}

function getPendingInvitesFor(userId) {
  const userInvites = pendingInvitesByUser.get(userId) || new Set();
  const inviteList = [];

  userInvites.forEach(inviteId => {
    const invite = invites.get(inviteId);
    if (invite && invite.status === 'pending') {
      inviteList.push(invite);
    }
  });

  return inviteList;
}

function isUserBlocked(fromUserId, toUserId) {
  const blockedSet = blockedUsers.get(toUserId);
  return blockedSet ? blockedSet.has(fromUserId) : false;
}

function blockUser(userId, blockUserId) {
  if (!blockedUsers.has(userId)) {
    blockedUsers.set(userId, new Set());
  }
  blockedUsers.get(userId).add(blockUserId);
}

function unblockUser(userId, unblockUserId) {
  const blockedSet = blockedUsers.get(userId);
  if (blockedSet) {
    blockedSet.delete(unblockUserId);
  }
}

function addClientConnection(userId, ws) {
  if (!clients.has(userId)) {
    clients.set(userId, new Set());
  }
  clients.get(userId).add(ws);
  console.log(`Added connection for user ${userId}. Total connections: ${clients.get(userId).size}`);
}

function removeClientConnection(userId, ws) {
  const userConnections = clients.get(userId);
  if (userConnections) {
    userConnections.delete(ws);
    if (userConnections.size === 0) {
      clients.delete(userId);
      console.log(`Removed last connection for user ${userId}`);
    } else {
      console.log(`Removed connection for user ${userId}. Remaining connections: ${userConnections.size}`);
    }
  }
}

function sendToUser(userId, message) {
  const userConnections = clients.get(userId);
  if (!userConnections || userConnections.size === 0) {
    console.log(`No connections found for user ${userId}`);
    return false;
  }

  let sentCount = 0;
  userConnections.forEach(ws => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(message));
      sentCount++;
    }
  });

  console.log(`Sent message to ${sentCount} connections for user ${userId}`);
  return sentCount > 0;
}

// Kept for backward compatibility or future use, but sendToUser is preferred
function sendToUsername(username, message) {
  const userInfo = usersByUserName.get(username);
  if (userInfo && userInfo.userId) {
    console.log(`Sending message to username: ${username} (id - ${userInfo.userId})`);
    return sendToUser(userInfo.userId, message);
  } else {
    console.log(`Could not find user to send message by username: ${username}`);
    return false;
  }
}

function isUserOnline(userId) {
  const userConnections = clients.get(userId);
  if (!userConnections) return false;

  // Check if user has at least one open connection
  for (const ws of userConnections) {
    if (ws.readyState === WebSocket.OPEN) {
      return true;
    }
  }
  return false;
}

/**
 * NEW: Consolidated registration and authentication logic.
 * This function handles new user registration, re-authentication, and forced takeovers.
 * @param {WebSocket} ws - The WebSocket connection.
 * @param {string} userId - The user's permanent ID.
 * @param {string} displayName - The user's desired display name.
 * @param {boolean} isForce - Whether to disconnect existing sessions for this user.
 * @returns {boolean} - True if authentication was successful, false otherwise.
 */
function performRegistration(ws, userId, displayName, isForce) {
  const wsId = ws._id;
  
  if (!userId) {
    console.warn(`[WS ${wsId}] Registration failed: userId is null or empty.`);
    ws.send(JSON.stringify({ type: 'register_error', message: 'A valid User ID is required.' }));
    return false;
  }

  const newDisplayName = displayName || userId; // Default display name to userId if not provided

  // --- Display Name Conflict Check ---
  const existingUserByName = usersByUserName.get(newDisplayName);
  if (existingUserByName) {
    if (existingUserByName.userId === userId) {
      console.log(`[WS ${wsId}] Display name '${newDisplayName}' is already linked to ${userId}, skipping conflict.`);
    } else {
      console.log(
        `[WS ${wsId}] Registration failed for ${userId}. Display name '${newDisplayName}' is already in use by ${existingUserByName.userId}.`,
      );
      ws.send(
        JSON.stringify({
          type: 'register_error',
          message: `Display name "${newDisplayName}" is already taken. Please choose another one.`,
        }),
      );
      return false;
    }
  }

  // --- Existing Session Check ---
  const existingConnections = clients.get(userId);
  if (existingConnections && existingConnections.size > 0) {
    if (!isForce) {
      
      console.log(`[WS ${wsId}] Registration failed for ${userId}. User is already connected.`);
      ws.send(JSON.stringify({
        type: 'register_error',
        message: 'This user is already connected elsewhere. Please logout first or force connect.'
      }));
      return false;
    }
    
    // Force disconnect existing connections
    console.log(`[WS ${wsId}] Force registering ${userId}. Disconnecting ${existingConnections.size} existing connections.`);
    existingConnections.forEach(existingWs => {
      if (existingWs !== ws) {
        existingWs.send(JSON.stringify({
          type: 'force_disconnected',
          message: 'Your session was disconnected because you logged in from another location.'
        }));
        existingWs.close();
      }
    });
    clients.delete(userId);
  }
  
  // --- Proceed with Registration ---
  
  // Get old user info (if it exists) to clean up old display name
  const oldUserInfo = usersByUserId.get(userId);
  if (oldUserInfo && oldUserInfo.userName !== newDisplayName) {
    console.log(`[WS ${wsId}] User ${userId} is changing name from '${oldUserInfo.userName}' to '${newDisplayName}'.`);
    usersByUserName.delete(oldUserInfo.userName);
  }

  // Set the new identity for this connection
  ws.myUserId = userId;
  ws.myUserName = newDisplayName;
  
  // Update all maps
  connectionsByWsId.set(wsId, { userId: userId, ws });
  addClientConnection(userId, ws);
  usersByUserId.set(userId, { userName: newDisplayName });
  usersByUserName.set(newDisplayName, { userId: userId });

  console.log(`User ${newDisplayName} (${userId}) is now online and searchable.`);
  
  // Send pending invites
  const pendingInvites = getPendingInvitesFor(userId);
  ws.send(JSON.stringify({
    type: 'pending_invites',
    invites: pendingInvites
  }));
  
  ws.send(JSON.stringify({
    type: 'joined',
    userId: userId,
    displayName: newDisplayName,
    isRegisteredUser: isRegisteredUserId(userId)
  }));
  return true;
}

/**
 * NEW: Attempts to auto-update a user's display name if a mismatch is detected.
 * This is part of Req 4.
 * @param {WebSocket} ws - The WebSocket connection.
 * @param {string} newDisplayName - The new display name from the request.
 * @returns {boolean} - True if update was successful or not needed, false if conflict.
 */
function attemptDisplayNameUpdate(ws, newDisplayName) {
  if (!newDisplayName || newDisplayName === ws.myUserName) {
    return true; // No update needed
  }
  
  // Check if new name is taken by *another* user
  const existing = usersByUserName.get(newDisplayName);
  if (existing && existing.userId !== ws.myUserId) {
    console.warn(`[WS ${ws._id}] User ${ws.myUserId} sent request with mismatched name '${newDisplayName}', but it's taken. Proceeding with old name '${ws.myUserName}'.`);
    return false; // Conflict
  }
  
  // Perform the update
  console.log(`[WS ${ws._id}] Auto-updating display name for ${ws.myUserId} from '${ws.myUserName}' to '${newDisplayName}'`);
  
  // Delete old name mapping
  usersByUserName.delete(ws.myUserName);
  
  // Add new name mappings
  usersByUserName.set(newDisplayName, { userId: ws.myUserId });
  usersByUserId.set(ws.myUserId, { userName: newDisplayName });
  
  // Update connection
  ws.myUserName = newDisplayName;
  
  // Propagate change to all pending invites (both sent and received)
  invites.forEach(invite => {
    if (invite.status === 'pending') {
      if (invite.fromUserId === ws.myUserId) {
        invite.fromUserName = newDisplayName;
      }
      if (invite.toUserId === ws.myUserId) {
        invite.toUserName = newDisplayName;
      }
    }
  });

  ws.send(JSON.stringify({
    type: 'display_name_updated',
    newDisplayName: newDisplayName,
    message: 'Your display name was updated based on your request.'
  }));

  return true;
}

// Cancels any pending invites between two specific users
function cancelPendingInvitesBetween(userA, userB) {
  invites.forEach((inv, id) => {
    if (
      inv &&
      inv.status === 'pending' &&
      (
        (inv.fromUserId === userA && inv.toUserId === userB) ||
        (inv.fromUserId === userB && inv.toUserId === userA)
      )
    ) {
      inv.status = 'cancelled';
      const set = pendingInvitesByUser.get(inv.toUserId);
      if (set) set.delete(id);
    }
  });
}

const server = http.createServer((req, res) => {
  const parsed = url.parse(req.url, true);

  if (req.method === 'GET' && parsed.pathname === '/.well-known/apple-app-site-association') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    const filePath = path.join(__dirname, '.well-known', 'apple-app-site-association');
    fs.createReadStream(filePath).pipe(res);
    return;
  }

  if (req.method === 'GET' && parsed.pathname === '/.well-known/assetlinks.json') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    const filePath = path.join(__dirname, '.well-known', 'assetlinks.json');
    fs.createReadStream(filePath).pipe(res);
    return;
  }

  if (req.method === 'GET' && parsed.pathname === '/invites') {
    const userId = parsed.query.userId;
    if (!userId) return json(res, 400, { error: 'userId required' });
    return json(res, 200, { invites: getPendingInvitesFor(userId) });
  }

  if (req.method === 'GET' && parsed.pathname === '/debug') {
    const debugInfo = {
      timestamp: new Date().toISOString(),
      connectedClients: Array.from(clients.keys()),
      onlineUsersByUserId: Object.fromEntries(usersByUserId.entries()),
      onlineUsersByName: Object.fromEntries(usersByUserName.entries()),
      totalUsersOnline: clients.size,
      totalConnections: Array.from(clients.values()).reduce((sum, connections) => sum + connections.size, 0),
      connectionsByUser: Object.fromEntries(
        Array.from(clients.entries()).map(([userId, connections]) => [
          userId,
          {
            count: connections.size,
            states: Array.from(connections).map(ws => ws.readyState)
          }
        ])
      ),
      invites: Object.fromEntries(invites.entries()),
      pendingInvitesByUser: Object.fromEntries(
        Array.from(pendingInvitesByUser.entries()).map(([k, v]) => [k, Array.from(v)])
      ),
      blockedUsers: Object.fromEntries(
        Array.from(blockedUsers.entries()).map(([k, v]) => [k, Array.from(v)])
      ),
      activePair: activePair,
      serverStats: {
        uptime: process.uptime(),
        memoryUsage: process.memoryUsage()
      }
    };
    return json(res, 200, debugInfo);
  }

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type'
    });
    return res.end();
  }

  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('OK');
});

const wss = new WebSocket.Server({ server });

wss.on('connection', function connection(ws) {
  
  // --- NEW: Attach identity info to the ws object itself ---
  ws.myUserId = null;
  ws.myUserName = null;
  // ---
  
  const wsId = ++wsCounter;
  ws._id = wsId;

  console.log(`New WebSocket connection: ID ${wsId}`);

  // Store connection info
  connectionsByWsId.set(wsId, { userId: null, ws });
  ws.send(JSON.stringify({ type: 'connected', message: 'Welcome. Please register.' }));

  ws.on('message', function(message) {
    console.log(`[WS ${wsId}] Received message from user ${ws.myUserId || 'NOT_AUTHED'}:`, JSON.parse(message.toString()));

    let msg;
    try {
      msg = JSON.parse(message);
    } catch (e) {
      console.log(`[WS ${wsId}] Invalid JSON received`);
      return;
    }

    // --- NEW Authentication Gate ---
    // Certain messages are allowed to authenticate a session.
    // All other messages require an *already* authenticated session.
    
    if (!ws.myUserId) {
      // User is NOT authenticated
      switch(msg.type) {
        case 'register':
          performRegistration(ws, msg.userId, msg.userName, false);
          return; // Stop processing this message
          
        case 'force_register':
          performRegistration(ws, msg.userId, msg.userName, true);
          return; // Stop processing this message

        case 'send_invite':
          // Implicitly register/authenticate (like a force_register)
          if (!performRegistration(ws, msg.fromUserId, msg.fromUserName, true)) {
            return; // Registration failed (e.g., name conflict)
          }
          // if successful, ws.myUserId is now set, so we break and let processing continue
          break;

        case 'migrate_identity':
          // This message is special, it needs to authenticate as the *old* user first
          if (!performRegistration(ws, msg.oldUserId, msg.userName, true)) {
            console.warn(`[WS ${wsId}] Migration failed: Could not authenticate as old user ${msg.oldUserId}`);
            return;
          }
          // Authentication as old user successful, proceed to migration logic
          break;

        default:
          // Any other message type
          console.log(`[WS ${wsId}] Message type '${msg.type}' rejected: User is not authenticated.`);
          ws.send(JSON.stringify({ type: 'auth_required', message: 'You must register or log in before performing this action.' }));
          return;
      }
    }
    
    // --- User is now GUARANTEED to be authenticated (ws.myUserId is set) ---

    // --- NEW: Handle all messages with a switch statement ---
    switch(msg.type) {

      // Auth messages are handled above, but if they arrive *after* auth,
      // they act as a re-auth or display name update.
      case 'register':
      case 'force_register':
        performRegistration(ws, msg.userId, msg.userName, msg.type === 'force_register');
        break;

      // --- NEW: Display Name Change (Req 3) ---
      case 'update_display_name':
        if (typeof msg.newDisplayName === 'string' && msg.newDisplayName.trim().length > 0) {
          if (attemptDisplayNameUpdate(ws, msg.newDisplayName.trim())) {
             // Success is handled in the function
          } else {
            // Send error if update failed (e.g., name taken)
            ws.send(JSON.stringify({
              type: 'update_error',
              message: `Display name "${msg.newDisplayName.trim()}" is already taken.`
            }));
          }
        } else {
          ws.send(JSON.stringify({ type: 'update_error', message: 'A valid newDisplayName is required.' }));
        }
        break;

      // Search for a user by ID first, then fall back to display name
      case 'search_user':
        if (typeof msg.username === 'string' || typeof msg.userId === 'string') {
          const requestedId = typeof msg.userId === 'string' ? msg.userId.trim() : '';
          const requestedName = typeof msg.username === 'string' ? msg.username.trim() : '';
          const providedQuery = typeof msg.searchQuery === 'string' ? msg.searchQuery.trim() : '';
          const normalizedQuery = providedQuery || requestedId || requestedName;

          let matchedUser = null;
          let lookupType = null;

          if (requestedId) {
            const targetById = usersByUserId.get(requestedId);
            if (targetById && isUserOnline(requestedId)) {
              matchedUser = { userId: requestedId, userName: targetById.userName };
              lookupType = 'userId';
            }
          }

          if (!matchedUser && requestedName) {
            const targetUser = usersByUserName.get(requestedName);
            if (targetUser && isUserOnline(targetUser.userId)) {
              matchedUser = { userId: targetUser.userId, userName: requestedName };
              lookupType = 'displayName';
            }
          }

          if (matchedUser) {
            console.log(`[WS ${wsId}] User search for '${normalizedQuery}': Found user ${matchedUser.userId} via ${lookupType}`);
            ws.send(JSON.stringify({
              type: 'user_search_result',
              found: true,
              userId: matchedUser.userId,
              userName: matchedUser.userName,
              lookupType,
              searchQuery: normalizedQuery,
              isRegisteredUser: isRegisteredUserId(matchedUser.userId)
            }));
          } else {
            const attemptedType = requestedId ? 'userId' : 'displayName';
            console.log(`[WS ${wsId}] User search for '${normalizedQuery}': Not found or offline.`);
            ws.send(JSON.stringify({
              type: 'user_search_result',
              found: false,
              lookupType: attemptedType,
              searchQuery: normalizedQuery
            }));
          }
        }
        break;

      // Send invite
      case 'send_invite':
        if (typeof msg.toUserId !== 'string' || typeof msg.toUserName !== 'string') {
          console.warn(`[WS ${wsId}] Invalid send_invite: toUserId or toUserName missing.`);
          break;
        }

        // --- REQ 4: Auto-update sender's display name if mismatched ---
        attemptDisplayNameUpdate(ws, msg.fromUserName);
        // We use ws.myUserName as the source of truth *after* the update attempt
        const fromUserName = ws.myUserName;

        // Check if target user is blocked
        if (isUserBlocked(ws.myUserId, msg.toUserId)) {
          ws.send(JSON.stringify({
            type: 'invite_error',
            message: 'Cannot send invite to this user'
          }));
          break;
        }

        // --- REQ 4: Check for target display name mismatch ---
        const targetUserInfo = usersByUserId.get(msg.toUserId);
        let effectiveToUserName = msg.toUserName;
        
        if (targetUserInfo && targetUserInfo.userName !== msg.toUserName) {
          console.warn(`[WS ${wsId}] Invite for ${msg.toUserId} had display name '${msg.toUserName}', but server record is '${targetUserInfo.userName}'. Using server record.`);
          effectiveToUserName = targetUserInfo.userName;
        } else if (!targetUserInfo && isUserOnline(msg.toUserId)) {
          // This can happen if user is online but not in our user maps (should be rare)
          console.warn(`[WS ${wsId}] Invite for ${msg.toUserId} but user has no userName record, using provided name '${msg.toUserName}'.`);
        }
        // ---

        const inviteId = generateInviteId();
        const invite = {
          id: inviteId,
          fromUserId: ws.myUserId,
          fromUserName: fromUserName, // Use the (potentially updated) name
          toUserId: msg.toUserId,
          toUserName: effectiveToUserName, // Use the corrected name
          fromUserIsRegistered: isRegisteredUserId(ws.myUserId),
          toUserIsRegistered: isRegisteredUserId(msg.toUserId),
          timestamp: new Date().toISOString(),
          deckCardCount: msg.deckCardCount ?? 55,
          deckJsonKey: msg.deckJsonKey,
          status: 'pending'
        };

        invites.set(inviteId, invite);

        // Add to recipient's pending invites
        if (!pendingInvitesByUser.has(msg.toUserId)) {
          pendingInvitesByUser.set(msg.toUserId, new Set());
        }
        pendingInvitesByUser.get(msg.toUserId).add(inviteId);

        // Notify recipient if online
        // --- FIX (Req 6): Send to toUserId, not toUserName ---
        const recipientOnline = sendToUser(msg.toUserId, {
          type: 'new_invite',
          invite: invite
        });

        console.log(`[WS ${wsId}] Invite sent. Recipient ${msg.toUserId} online: ${recipientOnline}`);

        ws.send(JSON.stringify({
          type: 'invite_sent',
          inviteId: inviteId
        }));
        break;

      // Respond to invite
      case 'respond_invite':
        if (typeof msg.inviteId !== 'string') break;
        
        const current_invite = invites.get(msg.inviteId);
        if (!current_invite || current_invite.toUserId !== ws.myUserId) {
          console.log(`[WS ${wsId}] Invalid invite response: ${msg.inviteId}`);
          break;
        }

        const response = msg.response; // 'accepted' or 'declined'
        current_invite.status = response;

        // Remove from pending
        const userInvites = pendingInvitesByUser.get(ws.myUserId);
        if (userInvites) {
          userInvites.delete(msg.inviteId);
        }
        
        // --- REQ 4: Auto-update responder's name if provided and mismatched ---
        if(msg.responderName) {
            attemptDisplayNameUpdate(ws, msg.responderName);
        }

        // Notify sender
        sendToUser(current_invite.fromUserId, {
          type: 'invite_response',
          inviteId: msg.inviteId,
          status: response,
          responder: ws.myUserName // Use guaranteed-correct name
        });

        // If accepted, start game
        if (response === 'accepted' && !activePair) {
          console.log(`[WS ${wsId}] Invite accepted, checking game start conditions`);
          const accepted_invite = invites.get(msg.inviteId);

          const player1 = accepted_invite.fromUserId;  // The inviter
          const player2 = ws.myUserId;        // The one who accepted

          const player1Online = isUserOnline(player1);
          const player2Online = isUserOnline(player2);

          console.log(`[WS ${wsId}] Player1 ${player1} online: ${player1Online}`);
          console.log(`[WS ${wsId}] Player2 ${player2} online: ${player2Online}`);

          if (player1Online && player2Online) {
            const seed = Math.floor(Math.random() * 2147483647);
            activePair = { a: player1, b: player2, seed };

            console.log(`[WS ${wsId}] Starting game with seed ${seed}`);

            // Send different messages to each player so they know their position
            sendToUser(accepted_invite.fromUserId, {
              type: 'ready',
              seed,
              deckJsonKey: accepted_invite.deckJsonKey,
              playerPosition: 'A', // First half of deck
              opponentId: accepted_invite.toUserId,
              opponentName: accepted_invite.toUserName // Send the name *they* have on record
            });

            sendToUser(accepted_invite.toUserId, {
              type: 'ready',
              seed,
              deckJsonKey: accepted_invite.deckJsonKey,
              playerPosition: 'B', // Second half of deck
              opponentId: accepted_invite.fromUserId,
              opponentName: accepted_invite.fromUserName // Send the name *they* have on record
            });
          } else {
            console.log(`[WS ${wsId}] Cannot start game - players not online`);
          }
        }
        break;

      // Block user
      case 'block_user':
        if (typeof msg.blockUserId === 'string') {
          blockUser(ws.myUserId, msg.blockUserId);

          // Cancel any pending invites between these users
          const myInvites = pendingInvitesByUser.get(ws.myUserId) || new Set();
          myInvites.forEach(inviteId => {
            const invite = invites.get(inviteId);
            if (invite && invite.fromUserId === msg.blockUserId) {
              invite.status = 'cancelled';
              myInvites.delete(inviteId);
            }
          });
          const theirInvites = pendingInvitesByUser.get(msg.blockUserId) || new Set();
          theirInvites.forEach(inviteId => {
             const invite = invites.get(inviteId);
             if (invite && invite.fromUserId === ws.myUserId) {
                invite.status = 'cancelled';
                theirInvites.delete(inviteId);
                // Also notify the (now blocked) sender
                sendToUser(msg.blockUserId, { type: 'invite_response', status: 'cancelled', inviteId: inviteId, responder: ws.myUserName });
             }
          });


          ws.send(JSON.stringify({
            type: 'user_blocked',
            blockedUserId: msg.blockUserId
          }));
        }
        break;

      // Unblock user
      case 'unblock_user':
        if (typeof msg.unblockUserId === 'string') {
          unblockUser(ws.myUserId, msg.unblockUserId);
          ws.send(JSON.stringify({
            type: 'user_unblocked',
            unblockedUserId: msg.unblockUserId
          }));
        }
        break;

      // Relay game moves between active pair only
      case 'move':
        if (activePair && ws.myUserId) {
          const other = (activePair.a === ws.myUserId) ? activePair.b :
                      (activePair.b === ws.myUserId ? activePair.a : null);
          if (other) {
            console.log(`[WS ${wsId}] Relaying move from ${ws.myUserId} to ${other}`);
            sendToUser(other, msg);
          }
        }
        break;
        
      case 'click':
        if (activePair && ws.myUserId) {
          const other = (activePair.a === ws.myUserId) ? activePair.b :
                      (activePair.b === ws.myUserId ? activePair.a : null);
          if (other) {
            console.log(`[WS ${wsId}] Relaying click from ${ws.myUserId} to ${other}`);
            sendToUser(other, { ...msg, fromUserId: ws.myUserId });
          }
        }
        break;
        
      case 'ack_click':
        if (activePair && ws.myUserId) {
          const other = (activePair.a === ws.myUserId) ? activePair.b :
                      (activePair.b === ws.myUserId ? activePair.a : null);
          if (other) {
            console.log(`[WS ${wsId}] Relaying round winner from ${ws.myUserId} to ${other}`);
            sendToUser(other, { ...msg, fromUserId: ws.myUserId });
          }
        }
        break;

      // Handle ready_to_draw messages
      case 'ready_to_draw':
        if (activePair && ws.myUserId) {
          const other = (activePair.a === ws.myUserId) ? activePair.b :
                      (activePair.b === ws.myUserId ? activePair.a : null);
          if (other) {
            console.log(`[WS ${wsId}] Relaying ready_to_draw from ${ws.myUserId} to ${other}`);
            sendToUser(other, {
              type: 'peer_ready_to_draw',
              fromUserId: ws.myUserId
            });
          }
        }
        break;

      // Game ended - clear active pair
      case 'game_ended':
        if (activePair && (activePair.a === ws.myUserId || activePair.b === ws.myUserId)) {
          console.log(`[WS ${wsId}] Game ended by ${ws.myUserId}`);
          const other = (activePair.a === ws.myUserId) ? activePair.b : activePair.a;
          if (other) {
            console.log(`[WS ${wsId}] Relaying game_ended from ${ws.myUserId} to ${other}`);
            sendToUser(other, { ...msg, fromUserId: ws.myUserId });
          }
          activePair = null;
        }
        break;

      // --- Identity Migration (Req 2) ---
      case 'migrate_identity':
        if (typeof msg.oldUserId !== 'string' || 
            typeof msg.newUserId !== 'string' ||
            ws.myUserId !== msg.oldUserId) {
          console.warn(`[WS ${wsId}] Invalid migration request. Old ID: ${msg.oldUserId}, Current ID: ${ws.myUserId}`);
          ws.send(JSON.stringify({ type: 'migration_error', message: 'Invalid migration request.' }));
          break;
        }
        
        console.log(`[WS ${wsId}] Migrating identity from ${msg.oldUserId} to ${msg.newUserId}`);
        
        const oldUserId = msg.oldUserId;
        const newUserId = msg.newUserId;
        const currentUserName = ws.myUserName;
        
        // 0. Check if newUserId is already taken
        if (clients.has(newUserId) || usersByUserId.has(newUserId)) {
            console.warn(`[WS ${wsId}] Migration failed: New user ID ${newUserId} already exists.`);
            ws.send(JSON.stringify({ type: 'migration_error', message: 'New user ID is already in use.' }));
            break;
        }

        // 1. Update ws connection identity
        ws.myUserId = newUserId;
        connectionsByWsId.set(wsId, { userId: newUserId, ws });
        
        // 2. Move all connections from old userId to new userId
        const oldConnections = clients.get(oldUserId);
        if (oldConnections) {
          clients.set(newUserId, oldConnections); // Move the Set
          clients.delete(oldUserId);
          
          // Update all connection maps (though wsId map is already done for this ws)
          oldConnections.forEach(conn => {
            connectionsByWsId.set(conn._id, { userId: newUserId, ws: conn });
            conn.myUserId = newUserId; // Update identity on all connections
          });
          
          console.log(`[WS ${wsId}] Transferred ${oldConnections.size} connections from ${oldUserId} to ${newUserId}`);
        }
        
        // 3. Update username mapping
        usersByUserId.delete(oldUserId);
        usersByUserId.set(newUserId, { userName: currentUserName });
        usersByUserName.set(currentUserName, { userId: newUserId }); // Overwrite old entry
        console.log(`[WS ${wsId}] Updated username mapping for ${currentUserName} to point to ${newUserId}`);
        
        // 4. Migrate pending invites - update as recipient
        const oldPendingInvites = pendingInvitesByUser.get(oldUserId);
        if (oldPendingInvites) {
          pendingInvitesByUser.set(newUserId, oldPendingInvites);
          pendingInvitesByUser.delete(oldUserId);
          
          oldPendingInvites.forEach(inviteId => {
            const invite = invites.get(inviteId);
            if (invite && invite.toUserId === oldUserId) {
              invite.toUserId = newUserId;
            }
          });
          console.log(`[WS ${wsId}] Migrated ${oldPendingInvites.size} pending invites to ${newUserId}`);
        }
        
        // 5. Update any invites where old user was the sender
        invites.forEach((invite, inviteId) => {
          if (invite.fromUserId === oldUserId) {
            invite.fromUserId = newUserId;
          }
        });
        
        // 6. Migrate blocked users lists
        const oldBlockedList = blockedUsers.get(oldUserId);
        if (oldBlockedList) {
          blockedUsers.set(newUserId, oldBlockedList);
          blockedUsers.delete(oldUserId);
        }
        
        blockedUsers.forEach((blockedSet, userId) => {
          if (blockedSet.has(oldUserId)) {
            blockedSet.delete(oldUserId);
            blockedSet.add(newUserId);
          }
        });
        
        // 7. Update active pair if user is in a game
        if (activePair) {
          if (activePair.a === oldUserId) {
            activePair.a = newUserId;
            console.log(`[WS ${wsId}] Updated active pair player A to ${newUserId}`);
          } else if (activePair.b === oldUserId) {
            activePair.b = newUserId;
            console.log(`[WS ${wsId}] Updated active pair player B to ${newUserId}`);
          }
        }
        
        // 8. Send confirmation
        ws.send(JSON.stringify({
          type: 'identity_migrated',
          oldUserId: oldUserId,
          newUserId: newUserId,
          displayName: currentUserName,
          message: 'Identity successfully migrated'
        }));
        
        console.log(`[WS ${wsId}] Identity migration complete: ${oldUserId} -> ${newUserId}`);
        break;

      default:
        console.log(`[WS ${wsId}] Unknown message type received: ${msg.type}`);
        break;
    }

  });

  ws.on('close', function() {
    console.log(`[WS ${wsId}] Connection closed for user: ${ws.myUserId}`);

    // Get identity from ws object *before* cleaning up
    const { myUserId, myUserName } = ws;

    if (myUserId) {
      removeClientConnection(myUserId, ws);

      // Check if the user has any remaining connections.
      if (!isUserOnline(myUserId)) {
        console.log(`User ${myUserId} (${myUserName}) is now fully offline.`);
        
        // --- FIX (Req 6): Remove from *both* user maps ---
        if (myUserName) {
          usersByUserName.delete(myUserName);
          console.log(`Removed ${myUserName} from searchable name map.`);
        }
        usersByUserId.delete(myUserId);
        console.log(`Removed ${myUserId} from user ID map.`);
        // ---
        
        // And if they were in a game, notify the other player.
        if (activePair && (activePair.a === myUserId || activePair.b === myUserId)) {
          const other = activePair.a === myUserId ? activePair.b : activePair.a;
          console.log(`Notifying opponent ${other} that ${myUserId} has left the game.`);
          sendToUser(other, { type: 'peer_left' });
          activePair = null;
        }
      }
    }

    connectionsByWsId.delete(wsId);
  });

  ws.on('error', function(error) {
    console.log(`[WS ${wsId}] Connection error:`, error);
  });
});

server.listen(PORT, () => {
  console.log(`Server (HTTP+WS) running on port ${PORT}`);
  console.log('Process ID:', process.pid);
});
