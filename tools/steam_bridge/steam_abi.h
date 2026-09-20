/* Minimal Steamworks flat C ABI for MapSync steam_bridge (-tags steamworks).
 *
 * Matches symbols exported by steam_api64.dll / libsteam_api from a current
 * Steamworks SDK. build_steamworks.bat links the redistributable import lib.
 */
#ifndef MAPSYNC_STEAM_ABI_H
#define MAPSYNC_STEAM_ABI_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef _WIN32
#define MAPSYNC_STEAM_API __declspec(dllimport)
#else
#define MAPSYNC_STEAM_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t HSteamPipe;
typedef int32_t HSteamUser;

typedef struct ISteamNetworkingMessages ISteamNetworkingMessages;
typedef struct ISteamUser ISteamUser;
typedef struct ISteamFriends ISteamFriends;

enum {
	k_ESteamNetworkingIdentityType_SteamID = 16,
	k_nSteamNetworkingSend_Reliable = 8,
	k_nSteamNetworkingSend_AutoRestartBrokenSession = 512,
	k_EFriendFlagImmediate = 0x04,
	k_iSteamNetworkingMessagesCallbacks = 1250,
	k_EResultOK = 1
};

/* Padded to the Steamworks SteamNetworkingIdentity size. */
typedef struct SteamNetworkingIdentity {
	int m_eType;
	int m_cbSize;
	uint64_t m_steamID64;
	uint8_t m_pad[128];
} SteamNetworkingIdentity;

typedef struct SteamNetworkingMessage_t {
	void *m_pData;
	int m_cbSize;
	uint32_t m_conn;
	SteamNetworkingIdentity m_identityPeer;
	int64_t m_nConnUserData;
	int64_t m_usecTimeReceived;
	int64_t m_nMessageNumber;
	void (*m_pfnFreeData)(struct SteamNetworkingMessage_t *);
	void (*m_pfnRelease)(struct SteamNetworkingMessage_t *);
	int m_nChannel;
	int m_nFlags;
	int64_t m_nUserData;
} SteamNetworkingMessage_t;

typedef struct FriendGameInfo_t {
	uint64_t m_gameID;
	uint32_t m_unGameIP;
	uint16_t m_usGamePort;
	uint16_t m_usQueryPort;
	uint64_t m_steamIDLobby;
} FriendGameInfo_t;

typedef struct CallbackMsg_t {
	HSteamUser m_hSteamUser;
	int m_iCallback;
	uint8_t *m_pubParam;
	int m_cubParam;
} CallbackMsg_t;

typedef struct SteamNetworkingMessagesSessionRequest_t {
	SteamNetworkingIdentity m_identityRemote;
} SteamNetworkingMessagesSessionRequest_t;

MAPSYNC_STEAM_API bool SteamAPI_Init(void);
MAPSYNC_STEAM_API void SteamAPI_Shutdown(void);
MAPSYNC_STEAM_API void SteamAPI_RunCallbacks(void);
MAPSYNC_STEAM_API bool SteamAPI_IsSteamRunning(void);
MAPSYNC_STEAM_API HSteamPipe SteamAPI_GetHSteamPipe(void);

MAPSYNC_STEAM_API void SteamAPI_ManualDispatch_Init(void);
MAPSYNC_STEAM_API void SteamAPI_ManualDispatch_RunFrame(HSteamPipe hSteamPipe);
MAPSYNC_STEAM_API bool SteamAPI_ManualDispatch_GetNextCallback(HSteamPipe hSteamPipe, CallbackMsg_t *pCallbackMsg);
MAPSYNC_STEAM_API void SteamAPI_ManualDispatch_FreeLastCallback(HSteamPipe hSteamPipe);

/* Interface accessors — versions match Steamworks SDK ~1.59+. If link fails,
 * retarget these names to the versions in your SDK's steam_api_flat.h. */
MAPSYNC_STEAM_API ISteamUser *SteamAPI_SteamUser_SteamAPI_v023(void);
MAPSYNC_STEAM_API uint64_t SteamAPI_ISteamUser_GetSteamID(ISteamUser *self);

MAPSYNC_STEAM_API ISteamFriends *SteamAPI_SteamFriends_SteamAPI_v017(void);
MAPSYNC_STEAM_API int SteamAPI_ISteamFriends_GetFriendCount(ISteamFriends *self, int iFriendFlags);
MAPSYNC_STEAM_API uint64_t SteamAPI_ISteamFriends_GetFriendByIndex(ISteamFriends *self, int iFriend, int iFriendFlags);
MAPSYNC_STEAM_API const char *SteamAPI_ISteamFriends_GetFriendPersonaName(ISteamFriends *self, uint64_t steamIDFriend);
MAPSYNC_STEAM_API bool SteamAPI_ISteamFriends_GetFriendGamePlayed(ISteamFriends *self, uint64_t steamIDFriend, FriendGameInfo_t *pFriendGameInfo);

MAPSYNC_STEAM_API ISteamNetworkingMessages *SteamAPI_SteamNetworkingMessages_SteamAPI_v002(void);
MAPSYNC_STEAM_API int SteamAPI_ISteamNetworkingMessages_SendMessageToUser(
	ISteamNetworkingMessages *self,
	const SteamNetworkingIdentity *identityRemote,
	const void *pubData,
	uint32_t cubData,
	int nSendFlags,
	int nRemoteChannel);
MAPSYNC_STEAM_API int SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel(
	ISteamNetworkingMessages *self,
	int nLocalChannel,
	SteamNetworkingMessage_t **ppOutMessages,
	int nMaxMessages);
MAPSYNC_STEAM_API bool SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser(
	ISteamNetworkingMessages *self,
	const SteamNetworkingIdentity *identityRemote);

#ifdef __cplusplus
}
#endif

#endif /* MAPSYNC_STEAM_ABI_H */
